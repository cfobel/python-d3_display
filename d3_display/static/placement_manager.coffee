class Curve
    constructor: (@_source=null, @_target=null, @_translate=null) ->
        if @_translate == null
            @_translate = (coords) -> coords
    translate: (t=null) =>
        if t != null
            @_translate = t
            @
        else
            @_translate
    target: (t=null) =>
        if t != null
            @_target = t
            @
        else
            @_target
    source: (s=null) =>
        if s != null
            @_source = s
            @
        else
            @_source
    d: () =>
        coords =
            source: @translate()(@source())
            target: @translate()(@target())
        if @source().y != @target().y and @source().x != @target().x
            path_text = d3.svg.diagonal()
                .source(coords.source)
                .target(coords.target)()
        else
            # The source and target share the same row or column.  Use an arc
            # to connect them rather than a diagonal.  A diagonal degrades to a
            # straight line in this case, making it difficult to distinguish
            # overlapping links.
            dx = coords.target.x - coords.source.x
            dy = coords.target.y - coords.source.y
            dr = Math.sqrt(dx * dx + dy * dy)
            if @source().y == @target().y and @source().x % 2 == 0
                flip = 1
            else if @source().x == @target().x and @source().y % 2 == 0
                flip = 1
            else
                flip = 0
            path_text = "M" + coords.source.x + "," + coords.source.y + "A" + dr + "," + dr + " 0 0," + flip + " " + coords.target.x + "," + coords.target.y
        return path_text


class SwapContext
    # Each `SwapContext` instance represents a set of swap configurations that
    # were generated.  In addition to storing each set of swaps, the
    # information for each swap is indexed by:
    #   -Whether or not the swap configuration was evaluated
    #   If the swap was evaluated, also index by:
    #       -The `from_` block of the swap configuration.
    #       -The `to` block of the swap configuration.
    #       -Whether or not the swap was accepted/skipped.
    #
    # Organizing swaps into `SwapContext` objects makes it straight-forward to
    # apply the swaps to a starting set of block positions.

    constructor: (placement) ->
        # Make a copy of the current block positions, which will be updated to
        # reflect the new positions of blocks involved in accepted swaps.
        @placement = placement
        @block_positions = placement.block_positions
        @all = []
        @participated = {}
        @not_participated = {}
        @accepted = {}
        @skipped = {}
        @by_from_block_id = {}
        @by_to_block_id = {}

    apply_swaps: (block_positions=null) ->
        if block_positions == null
            block_positions = @block_positions
        # Make a copy of the block positions
        block_positions = $.extend(true, [], block_positions)
        # Update the block positions array based on the accepted swaps in the
        # current context.
        for swap_i,swap_info of @accepted
            if swap_info.swap_config.master > 0
                if swap_info.swap_config.ids.from_ >= 0
                    from_d = block_positions[swap_info.swap_config.ids.from_]
                    [from_d.x, from_d.y] = swap_info.swap_config.coords.to
                if swap_info.swap_config.ids.to >= 0
                    to_d = block_positions[swap_info.swap_config.ids.to]
                    [to_d.x, to_d.y] = swap_info.swap_config.coords.from_
        return block_positions

    placement_with_swaps_applied: () =>
        options =
            block_positions: @apply_swaps(@placement.block_positions)
            net_to_block_ids: @placement.net_to_block_ids
            block_to_net_ids: @placement.block_to_net_ids
            block_net_counts: @placement.block_net_counts
        new Placement(options)

    compute_delta_cost: (d) ->
        result = @compute_delta_costs(d)
        sum = (d) -> _.reduce(d, ((a, b) -> a + b), 0)
        return sum(result.to_costs.new_) -
                sum(result.to_costs.old) +
            sum(result.from_costs.new_) -
                sum(result.from_costs.old)

    delta_costs_summary: (d) ->
        summary = (costs) ->
            old = $M(costs.old)
            new_ = $M(costs.new_)
            delta = new_.subtract(old)
            new_.flatten().join(" + ") + " - " + old.flatten().join(" - ") +
                " (" + delta.flatten().join(" + ") + ")"
        from_summary = if d.from_costs.old? then summary(d.from_costs) else ""
        to_summary = if d.to_costs.old? then summary(d.to_costs) else ""
        "{" + from_summary + "} + {" + to_summary + "}"
    
    compute_delta_costs: (d) ->
        costs = {}
        for name,details of {'from_': d.from_, 'to': d.to}
            costs[name] = {}
            for k in ["old", "new"]
                try
                    sums = details[k + "_sums"]
                    squared_sums = details[k + "_squared_sums"]
                    if k == "new"
                        k = "new_"
                    if sums.length
                        costs[name][k] = @_compute_costs(sums, squared_sums,
                                     details.net_block_counts)
                    else
                        costs[name][k] = null
                catch e
                    console.log("[compute_delta_costs] ERROR:", name, k, details, e)
        return from_costs: costs['from_'], to_costs: costs['to']

    _compute_costs: (sums, squared_sums, net_block_counts) ->
        x_costs = []
        y_costs = []
        for i in [0..net_block_counts.length - 1]
            result = Math.round(
                sums[i][0] +
                sums[i][1] +
                squared_sums[i][0] +
                squared_sums[i][1] +
                net_block_counts[i][1])
            costs.push(result)
            #return _.reduce(costs, ((a, b) -> a + b), 0);
        return costs

    accepted_count: () => Object.keys(@accepted).length
    skipped_count: () => Object.keys(@skipped).length
    participated_count: () => Object.keys(@participated).length
    total_count: () => @all.length
    process_swap: (swap_info) =>
        # Record information for current swap in `all` array, as well
        # as indexed by:
        #   -Whether or not the swap configuration was evaluated
        #   If the swap was evaluated, also index by:
        #       -The `from_` block of the swap configuration.
        #       -The `to` block of the swap configuration.
        #       -Whether or not the swap was accepted/skipped.
        @all.push(swap_info)
        if swap_info.swap_config.participate
            if swap_info.swap_config.ids.from_ >= 0
                if swap_info.swap_config.ids.from_ of @by_from_block_id
                    block_swap_infos = @by_from_block_id[swap_info.swap_config.ids.from_]
                    block_swap_infos.push(swap_info)
                else
                    block_swap_infos = [swap_info]
                    @by_from_block_id[swap_info.swap_config.ids.from_] = block_swap_infos
            if swap_info.swap_config.ids.to >= 0
                if swap_info.swap_config.ids.to of @by_to_block_id
                    block_swap_infos = @by_to_block_id[swap_info.swap_config.ids.to]
                    block_swap_infos.push(swap_info)
                else
                    block_swap_infos = [swap_info]
                    @by_to_block_id[swap_info.swap_config.ids.to] = block_swap_infos
            @participated[swap_info.swap_i] = swap_info
            if swap_info.swap_result.swap_accepted
                @accepted[swap_info.swap_i] = swap_info
            else
                @skipped[swap_info.swap_i] = swap_info
        else
            @not_participated[swap_info.swap_i] = swap_info

    set_swap_link_data: (placement_grid) ->
        # Create a d3 diagonal between the blocks involved in each swap
        # configuration in the current context.
        swap_links = placement_grid.grid.selectAll(".swap_link").data(@all)
        swap_links.enter()
            .append("svg:path")
            .attr("class", "swap_link")
            .attr("id", (d) -> "id_swap_link_" + d.swap_i)
            .style("fill", "none")
            .style("pointer-events", "none")
            .style("stroke", "none")
            .style("stroke-width", 1.5)
            .style("opacity", 0)
        swap_links.exit().remove()

    from_ids: (swap_dict, only_master=false) ->
        (swap_info.swap_config.ids.from_ for swap_id,swap_info of swap_dict when swap_info.swap_config.ids.from_ >= 0 and (not only_master or swap_info.swap_config.master > 0))
    to_ids: (swap_dict, only_master=false) -> (swap_info.swap_config.ids.to for swap_id,swap_info of swap_dict when swap_info.swap_config.ids.to >= 0 and (not only_master or swap_info.swap_config.master > 0))

    block_element_classes: (block_ids) -> (".block_" + id for id in block_ids)

    accepted_count: () => Object.keys(@accepted).length

    update_block_formats: (placement_grid) ->
        g = placement_grid.grid
        g.selectAll(".block")
            .style("stroke-width", (d) -> if placement_grid.selected(d.block_id) then 2 else 1)
            .style("fill-opacity", (d) -> if placement_grid.selected(d.block_id) then 1.0 else 0.5)

        colorize = (block_ids, fill_color, opacity=null) =>
            if block_ids.length <= 0
                return
            g.selectAll(@block_element_classes(block_ids).join(", "))
                .style("fill", fill_color)
                .style("opacity", opacity ? 1.0)
        colorize(@from_ids(@not_participated), "red", 0.5)
        colorize(@to_ids(@skipped, true), "yellow")
        colorize(@from_ids(@skipped, true), "darkorange")
        colorize(@from_ids(@accepted, true), "darkgreen")
        colorize(@to_ids(@accepted, true), "limegreen")

    update_link_formats: (placement_grid) ->
        # Update the style and end-point locations for each swap link.
        swap_links = placement_grid.grid.selectAll(".swap_link")
        curve = new Curve()
        curve.translate(placement_grid.cell_center)
        swap_links.style("stroke-width", 1)
            .style("opacity", (d) ->
                if not d.swap_config.master and d.swap_config.participate
                    return 0.0
                else if d.swap_result.swap_accepted
                    return 0.9
                else if not d.swap_config.participate
                    return 0.35
                else
                    return 0.8
            )
            .style("stroke", (d) ->
                if d.swap_result.swap_accepted
                    return "green"
                else if not d.swap_config.participate
                    return "red"
                else
                    return "gold"
            )
        swap_links.attr("d", (d) =>
                [from_x, from_y] = d.swap_config.coords.from_
                from_coords = x: from_x, y: from_y
                [from_x, from_y] = d.swap_config.coords.to
                to_coords = x: from_x, y: from_y
                curve.source(from_coords).target(to_coords)
                @_latest_curve = curve
                curve.d()
            )

    connected_block_ids: (block_id) => (b.block_id for b in @connected_blocks(block_id))

    deep_connected_block_ids: (block_ids_input, include_initial=true) =>
        # Store block_ids in dictionary-like object for fast membership test
        block_ids = {} #block_ids_input[..]
        connected_block_ids = block_ids_input[..]
        for block_id in block_ids_input
            block_ids[block_id] = null
            ids = @connected_block_ids(block_id)
            connected_block_ids = connected_block_ids.concat(ids)
        connected_block_ids = _.uniq(connected_block_ids)
        return (+i for i in connected_block_ids when include_initial or not (i of block_ids))

    connected_blocks: (block_id) =>
        # Return list of blocks that are connected to the block with ID
        # `block_id` and that were involved involved in any swaps within the
        # current swap context.
        connected_blocks = [@block_positions[block_id]]
        if block_id of @by_from_block_id
            # Highlight any blocks that involve the current block as the `from`
            # block id
            for swap_info in @by_from_block_id[block_id]
                if swap_info.swap_config.ids.to >= 0
                    block = @block_positions[swap_info.swap_config.ids.to]
                    connected_blocks.push(block)
        else if block_id of @by_to_block_id
            # Highlight any blocks that involve the current block as the `to`
            # block id
            for swap_info in @by_to_block_id[block_id]
                if swap_info.swap_config.ids.to >= 0
                    block = @block_positions[swap_info.swap_config.ids.from_]
                    connected_blocks.push(block)
        return _.uniq(connected_blocks)


class Placement
    constructor: (options) ->
        @block_positions = options.block_positions
        @net_to_block_ids = options.net_to_block_ids
        @block_to_net_ids = options.block_to_net_ids
        @block_net_counts = options.block_net_counts


class PlacementManager extends Mixin
    setup: ->
        @placements = []
        @swap_contexts = {}
    last_i_with_swap_context: =>
        for i in [@placements.length..-1]
            if i of @swap_contexts
                return i
        return -1
    append_placement: (placement) ->
        @placements.push(placement)
        obj = @
        $(obj).trigger(type: "placement_added", placement: placement, placement_count: obj.placements.length)
        placement
    append_swap_context: (swap_context) ->
        ###
        Apply the swaps from the swap context to the most recent placement and
        append the result as the latest placement.  Also, save the current swap
        context with the index of the placement it was applied to as the key.
        ###
        i = @placements.length
        # TODO: verify swap application code
        placement = swap_context.placement_with_swaps_applied()
        @placements.push(placement)
        # N.B. `swap_contexts` is an object/dictionary
        @swap_contexts[i] = swap_context
        $(@).trigger(type: "swap_context_added", swap_context: swap_context, swap_context_i: i)
        $(@).trigger(type: "placement_added", placement: placement, placement_count: @placements.length)
        placement


class RemotePlacementManager extends EchoJsonController
    constructor: (options) ->
        PlacementManager::augment this
        @nullmq_context = options.nullmq_context
        @action_uri = options.action_uri
        @status_uri = options.status_uri
        @status_fe = @nullmq_context.socket(nullmq.SUB)
        @status_fe.connect(@status_uri)
        @status_fe.setsockopt(nullmq.SUBSCRIBE, "")
        @status_fe.recvall(@process_status_update)
        @_outstanding_placement_requests = 0
        @_swaps_in_progress = false
        @_iteration_in_progress = false
        @_do_iteration_timeout = null
        super @nullmq_context, @action_uri

    do_request: (message, on_recv) =>
        _on_recv = (response) =>
            #if ("error" of response) and response.error != null
            if not ("result" of response) or ("error" of response) and
                    response.error != null
                error = new Error(response.error)
                @_last_error = error
                throw error
            on_recv(response)
        super message, _on_recv

    do_iterations: (count, on_completed=null) =>
        obj = @
        @_outstanding_placement_requests += count
        stop_length = @placements.length + count
        do_iterations_id = $(obj).on("placement_added.do_iterations", () =>
            console.log("[do_iterations]:", @placements.length, stop_length, count, @_outstanding_placement_requests)
            if @placements.length >= stop_length
                $(obj).off("placement_added.do_iterations")
                if on_completed
                    on_completed(placement: @placements[@placements.length - 1])
        )
        @do_iteration(false)

    do_iteration: (increment=true)=>
        if @_iteration_in_progress
            #@_do_iteration_timeout = setTimeout((() => @do_iteration(false)), 50)
            @_do_iteration_timeout = setTimeout((() => @do_iteration(false)), 5000)
        else
            # Record the current number of placements so we can verify
            # later that the number of placements has increased.
            starting_count = @placements.length
            if increment
                @_outstanding_placement_requests += 1
            @_iteration_in_progress = true
            @do_request({"command": "iter__next"}, () =>
                # Here we subtract the observed change in the number of
                # placements from the number of outstanding placement
                # requests.
                @_outstanding_placement_requests -= @placements.length - starting_count
                @_outstanding_placement_requests = Math.max(@_outstanding_placement_requests, 0)
                @_iteration_in_progress = false;
                if @_outstanding_placement_requests > 0
                    @do_iteration(false)
            )

    process_status_update: (message) =>
        status_message = @deserialize(message)
        if status_message.type == 'swaps_start'
            # Create a new swap context
            @_swap_context = new SwapContext(@placements[@placements.length - 1])
            @_swaps_in_progress = true
            #console.log("[process_status_update] swaps_start")
        else if status_message.type == 'swap_info'
            @_swap_context.process_swap(status_message)
            #console.log("[process_status_update] swap_info")
        else if status_message.type == 'swaps_end'
            # We've reached the end of this round of swaps.  We can now
            # add the completed swap context to the `placement_manager`
            @_swaps_in_progress = false
            @append_swap_context(@_swap_context)
            #console.log("[process_status_update] swaps_end")
        else if status_message.type == 'placement'
            placement = @placements[@placements.length - 1]
            options =
                block_positions: translate_block_positions(status_message.block_positions)
                net_to_block_ids: placement.net_to_block_ids
                block_to_net_ids: placement.block_to_net_ids
                block_net_counts: placement.block_net_counts
            @append_placement(new Placement(options))
        else
            console.log(status_message, "[process_status] unknown message type: " + status_message.type)


@translate_block_positions = (block_positions) ->
    data = new Array()
    for position, i in block_positions
        item =
            block_id: i
            x: position[0]
            y: position[1]
            z: position[2]
        data.push(item)
    return data


@PlacementManager = PlacementManager
@RemotePlacementManager = RemotePlacementManager
@Placement = Placement
@SwapContext = SwapContext
