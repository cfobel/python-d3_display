class Net
    constructor: (@net_id, @block_ids) ->
        #@net_class =  'net_' + @net_id
        #@grid.grid.append("g").attr("class", 'net ' + @net_class)

    element: () -> d3.selectAll('.' + @net_class)

    block_coords: ->
        coords = []
        for b in @block_ids
            p = @grid.block_positions[b]
            coords.push(x: p.x, y: p.y)
        coords
    center_of_gravity: ->
        x_sum = 0
        y_sum = 0
        coords = @block_coords()
        for c in coords
            x_sum += c.x
            y_sum += c.y
        x: x_sum / coords.length, y: y_sum / coords.length
    highlight_blocks: () ->
        for b in @block_ids
            d3.select(".block_" + b)
                .style("stroke-width", "5px")
                .style("opacity", 0.8)
    unhighlight_blocks: () ->
        for b in @block_ids
            d3.select(".block_" + b)
                .style("stroke-width", "1px")
                .style("opacity", 0.2)
    unhighlight: () =>
        cog = @element().selectAll(".center_of_gravity")
        links = @element().selectAll(".net_link").remove()
        console.log("unhighlight", cog, links, @)
        cog.remove()
        links.remove()
        @unhighlight_blocks()
    highlight: () ->
        @highlight_blocks()
        @draw_links()
        cog = @grid.cell_center(@center_of_gravity())
        @element().append("circle")
            .attr("class", "center_of_gravity")
            .attr("data-net_id", @net_id)
            .attr("cx", cog.x)
            .attr("cy", cog.y)
            .attr("r", 8)
            .style("fill", "steelblue")
    draw_links: ->
        root_coords = @grid.cell_center(@center_of_gravity())
        target_coords = _.map(@block_coords(), @grid.cell_center)
        net_links = @element().selectAll(".net_link")
          .data(target_coords, (d, i) -> [root_coords, d])
        net_links.enter()
          .append("line")
            .attr("class", "net_link")
            .attr("pointer-events", "none")
        net_links.exit().remove()
        net_links.attr("x1", root_coords.x)
            .attr("y1", root_coords.y)
            .attr("x2", (d) -> d.x)
            .attr("y2", (d) -> d.y)
            .style("stroke", "black")
            .style("stroke-opacity", 0.7)


class PlaceContext
    constructor: (@net_to_block_ids, @block_to_net_ids, @block_net_counts) ->

    connected_block_ids: (block_id) =>
        try
            connected_block_ids = []
            net_ids = @block_to_net_ids[block_id]
            for i in [0..@block_net_counts[block_id] - 1]
                net_id = net_ids[i]
                for b in @net_to_block_ids[net_id]
                    if b != block_id
                        connected_block_ids.push(b)
            return _.sortBy(_.uniq(connected_block_ids), (v) -> v) #, (name: i for i in [0..10])]
        catch error
            @_last_error = error
            throw error

    connected_block_ids_by_root_block_ids: (block_ids) =>
        (root: b,  connected_block_ids: @connected_block_ids(b) for b in block_ids)

    nets_by_block_id: (block_ids) ->
        nets = {}
        for b in block_ids
            nets[b] = (@net_by_id(n) for n in @block_to_net_ids[b] when n >= 0)
        nets

    map_nets_by_block_id: (block_ids, f) ->
        nets_by_block_id = @nets_by_block_id(block_ids)
        results = []
        for b, nets of nets_by_block_id
            results.push(_.map(nets, f))
        results

    # TODO: group all view methods
    net_by_id: (net_id) =>
        block_ids = @net_to_block_ids[net_id]
        #return new Net(net_id, block_ids)
        return block_ids

    # TODO: group all view methods
    select_block_elements_by_ids: (block_ids) =>
        if block_ids.length > 0
            block_element_ids = (".block_" + i for i in block_ids)
            return @placement_grid.grid.selectAll(block_element_ids.join(","))
        else
            # Empty selection
            return d3.select()

    # TODO: group all view methods
    highlight_block_swaps: (block_ids) =>
        if @swap_context_i >= 0 and block_ids.length
            c = @current_swap_context()
            connected_block_ids = c.deep_connected_block_ids(block_ids, false)
            @placement_grid.grid.selectAll(".block")
              .filter((d) -> not (d.block_id in block_ids) and not (d.block_id in connected_block_ids))
              .style("opacity", 0.2)
              #console.log("highlight_block_swaps", block_ids, connected_block_ids)
            @select_block_elements_by_ids(block_ids)
                .style("opacity", 1.0)
                .style("fill-opacity", 1.0)
                .style("stroke-width", 3)
            @select_block_elements_by_ids(connected_block_ids)
                .style("opacity", 0.65)
                .style("fill-opacity", 1.0)
                .style("stroke-width", 3)
            @placement_grid.grid.selectAll(".link")
                .style("opacity", 0.1)
            @select_link_elements_by_block_ids(block_ids)
                .style("stroke-width", 2)
                .style("opacity", 1)

    # TODO: group all view methods
    unhighlight_block_swaps: (block_ids) =>
        #console.log("unhighlight_block_swaps", block_ids)
        if @swap_context_i > 0
            c = @current_swap_context()
            c.update_block_formats(@placement_grid)
            c.update_link_formats(@placement_grid)
            block_ids = @placement_grid.selected_block_ids()
            if block_ids.length
                @highlight_block_swaps(block_ids)

    # TODO: group all view methods
    apply_to_block_swaps: (block_id, callback) =>
        try
            c = this.current_swap_context()
        catch e
            if e.code and e.code == -100
                return []
            else
                throw e

        # Apply the callback function to each block involved in any swap where
        # either the `from` or `to` block ID is `block_id`.
        for block in c.connected_blocks(block_id)
            callback(block)


@PlaceContext = PlaceContext
