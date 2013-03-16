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

    constructor: (@placement) ->
        # Make a copy of the current block positions, which will be updated to
        # reflect the new positions of blocks involved in accepted swaps.
        @block_positions = @placement.block_positions
        @block_infos = translate_block_positions(@block_positions)
        @all = []
        @participated = {}
        @not_participated = {}
        @accepted = {}
        @skipped = {}
        @by_from_block_id = {}
        @by_to_block_id = {}

    apply_swaps: (block_infos=null) ->
        if block_infos == null
            block_infos = @block_infos
        # Make a copy of the block positions
        block_infos = $.extend(true, [], block_infos)
        #console.log('apply_swaps', block_infos)

        # Update the block positions array based on the accepted swaps in the
        # current context.
        for swap_i,swap_info of @accepted
            if swap_info.swap_config.master > 0
                if swap_info.swap_config.ids.from_ >= 0
                    #console.log('swap_info.swap_config.ids.from_', swap_info.swap_config.ids.from_)
                    from_d = block_infos[+swap_info.swap_config.ids.from_]
                    from_d.x = swap_info.swap_config.coords.to.x
                    from_d.y = swap_info.swap_config.coords.to.y
                if swap_info.swap_config.ids.to >= 0
                    to_d = block_infos[+swap_info.swap_config.ids.to]
                    to_d.x = swap_info.swap_config.coords.from_.x
                    to_d.y = swap_info.swap_config.coords.from_.y
        return block_infos

    #placement_with_swaps_applied: () =>
        #options =
            #block_positions: @apply_swaps(@placement.block_positions)
            #net_to_block_ids: @placement.net_to_block_ids
            #block_to_net_ids: @placement.block_to_net_ids
            #block_net_counts: @placement.block_net_counts
        #new Placement(options)

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
        swap_links.exit().remove()

    from_ids: (swap_dict, only_master=false) ->
        (swap_info.swap_config.ids.from_ for swap_id,swap_info of swap_dict when swap_info.swap_config.ids.from_ >= 0 and (not only_master or swap_info.swap_config.master > 0))
    to_ids: (swap_dict, only_master=false) -> (swap_info.swap_config.ids.to for swap_id,swap_info of swap_dict when swap_info.swap_config.ids.to >= 0 and (not only_master or swap_info.swap_config.master > 0))

    block_element_classes: (block_ids) -> (".block_" + id for id in block_ids)

    accepted_count: () => Object.keys(@accepted).length

    update_block_formats: (placement_grid) ->
        ###
        # Possible class combinations:
        #   master, non_participate
        #   non_master, non_participate
        #
        #   master, skipped
        #   non_master, skipped
        #
        #   master, accepted
        #   non_master, accepted
        #
        # However, note that 
        ###
        colorize = (block_ids, true_classes=[], false_classes=[]) =>
            if block_ids.length <= 0
                return
            g = placement_grid.grid
            block_elements = g.selectAll(@block_element_classes(block_ids).join(", "))
            for class_ in true_classes
                block_elements.classed(class_, true)
            for class_ in false_classes
                block_elements.classed(class_, false)
        @clear_classes(placement_grid)

        colorize(@from_ids(@not_participated), ['swap_block', 'master', 'non_participate'])
        colorize(@to_ids(@skipped, true), ["swap_block", "non_master", "skipped"])
        colorize(@from_ids(@skipped, true), ["swap_block", "master", "skipped"])
        colorize(@from_ids(@accepted, true), ["swap_block", "master", "accepted"])
        colorize(@to_ids(@accepted, true), ["swap_block", "non_master", "accepted"])

    clear_classes: (placement_grid, selection=null) =>
        if not (selection?)
            selection = placement_grid.grid.selectAll('.swap_block')

        for c in ['master', 'non_master', 'non_participate', 'accepted', 'skipped']
            selection.classed(c, false)

    update_link_formats: (placement_grid) ->
        # Update the style and end-point locations for each swap link.
        swap_links = placement_grid.grid.selectAll(".swap_link")
        curve = new coffee_helpers.Curve()
        curve.translate(placement_grid.cell_center)
        swap_links.each((d) ->
                d3.select(this)
                    .classed('non_master', false)
                    .classed('master', false)
                    .classed('accepted', false)
                    .classed('non_participate', false)
                    .classed('skipped', false)
                if not d.swap_config.master and d.swap_config.participate
                    d3.select(this).classed('non_master', true)
                else
                    d3.select(this).classed('master', true)

                if d.swap_result.swap_accepted
                    d3.select(this).classed('accepted', true)
                else if not d.swap_config.participate
                    d3.select(this).classed('non_participate', true)
                else
                    d3.select(this).classed('skipped', true)
            )
        swap_links.attr("d", (d) =>
                from_coords = d.swap_config.coords.from_
                to_coords = d.swap_config.coords.to
                curve.source(from_coords).target(to_coords)
                @_latest_curve = curve: curve, d: d, coords:
                    from_: from_coords
                    to: to_coords
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
        # Return list of block positions (i.e., coordinates) for blocks that
        # are connected to the block with ID `block_id` and that were involved
        # involved in any swaps within the current swap context.
        connected_blocks = [@block_infos[block_id]]
        if block_id of @by_from_block_id
            # Highlight any blocks that involve the current block as the `from`
            # block id
            for swap_info in @by_from_block_id[block_id]
                if swap_info.swap_config.ids.to >= 0
                    block = @block_infos[swap_info.swap_config.ids.to]
                    connected_blocks.push(block)
        else if block_id of @by_to_block_id
            # Highlight any blocks that involve the current block as the `to`
            # block id
            for swap_info in @by_to_block_id[block_id]
                if swap_info.swap_config.ids.to >= 0
                    block = @block_infos[swap_info.swap_config.ids.from_]
                    connected_blocks.push(block)
        return _.uniq(connected_blocks)


@SwapContext = SwapContext
