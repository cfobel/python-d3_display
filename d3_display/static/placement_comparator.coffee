class BasePlacementComparator
    constructor: (a_container, b_container) ->
        @containers =
            a: a_container
            b: b_container

        @templates = @get_templates()

        @grid_containers =
            a: @containers.a.append('div').attr('class', 'grid_a')
            b: @containers.b.append('div').attr('class', 'grid_b')

        console.log('[BasePlacementComparator]', @grid_containers)
        @grid_containers.a.style("border", "solid #9e6ab8")
        @grid_containers.b.style("border", "solid #7bb33d")

        @opposite_labels =
            a: 'b'
            b: 'a'

        @grids =
            a: null
            b: null

    get_templates: () ->
        _.templateSettings = interpolate: /\{\{(.+?)\}\}/g
        template_texts =
            manager_selector: d3.select('.placement_manager_grid_selector_template').html()
        templates = {}
        for k, v of template_texts
            templates[k] = _.template(v)
        return templates

    reset_grid_a: () =>
        @grid_containers.a.html('')
        @grids.a = new PlacementGrid(@grid_containers.a)
        @_connect_grid_signals(@grids.a)
        if @grids.b?
            @grids.b.set_zoom([0, 0], 1, false)

    reset_grid_b: () =>
        @grid_containers.b.html('')
        @grids.b = new PlacementGrid(@grid_containers.b)
        @_connect_grid_signals(@grids.b)
        if @grids.a?
            @grids.a.set_zoom([0, 0], 1, false)

    compare: () =>
        if not @grids.a? or not @grids.b?
            # We must have two grids to do a comparison
            throw '[warning] We must have two grids to do a comparison'
        else if @grids.a.block_positions.length != @grids.b.block_positions.length
            throw '[warning] The grids must have same number of blocks.'
        same = {}
        different = {}
        for data,i in _.zip(@grids.a.block_positions, @grids.b.block_positions)
            [a, b] = ([v.x, v.y, v.z] for v in data)
            if not coffee_helpers.json_compare(a, b)
                different[i] = {a: a, b: b}
            else
                same[i] = a
        return same: same, different: different

    _get_block_rects: (grid, block_ids) =>
        return ((new Block(block_id).rect(grid)[0][0]) for block_id in block_ids)

    select_blocks_by_id: (block_ids, grid=null) =>
        _update = (orig, g) =>
            orig.concat(@_get_block_rects(g, block_ids))

        block_rects = []
        if grid?
            # If grid was specified, only selected matching blocks from that
            # grid.
            block_rects = @_get_block_rects(grid, block_ids)
        else
            # If no grid was specified, select matching blocks from any grid
            # available.
            if @grids.a?
                block_rects = _update(block_rects, @grids.a)
            if @grids.b?
                block_rects = _update(block_rects, @grids.b)
        # Return d3 selection
        d3.selectAll(block_rects)

    set_block_positions: (grid, block_positions) ->
        grid.set_raw_block_positions(block_positions)

    set_block_positions_grid_a: (block_positions) =>
        @set_block_positions(@grids.a, block_positions)
        @highlight_comparison()
        @update_selected()

    set_block_positions_grid_b: (block_positions) =>
        @set_block_positions(@grids.b, block_positions)
        @highlight_comparison()
        @update_selected()

    _connect_grid_signals: (grid) =>
        $(grid).on("block_mouseover", (e) =>
            if @grids.a?
                @grids.a.update_header(e.block)
                if e.grid == @grids.b
                    e.block.rect(@grids.a)
                        .classed('hovered', true)
            if @grids.b?
                @grids.b.update_header(e.block)
                if e.grid == @grids.a
                    e.block.rect(@grids.b)
                        .classed('hovered', true)
        )
        $(grid).on("block_mouseout", (e) =>
            if @grids.b? and e.grid == @grids.a
                e.block.rect(@grids.b)
                    .classed('hovered', false)
            if @grids.a? and e.grid == @grids.b
                e.block.rect(@grids.a)
                    .classed('hovered', false)
        )
        $(grid).on("block_click", (e) =>
            @select_blocks_by_id([e.block.id]).classed('selected', (d) ->
                d.selected = e.d.selected
                d.selected
            )
        )
        $(grid).on("zoom_updated", (e) =>
            # When zoom is updated on grid a, update grid b to match.
            # N.B. We must set `signal=false`, since otherwise we would end up
            # in an endless ping-pong back-and-forth between the two grids.
            if @grids.a? and e.grid == @grids.a and @grids.b?
                @grids.b.set_zoom(e.translate, e.scale, false)
            else if @grids.b? and e.grid == @grids.b and @grids.a?
                @grids.a.set_zoom(e.translate, e.scale, false)
        )

    block_emphasize: (grid, block) =>
        if not grid?
            return
        block.rect(grid).style("fill-opacity", 1.0)
        grid.update_header(block)

    block_deemphasize: (grid, block) =>
        if not grid?
            return
        block.rect(grid).style("fill-opacity", (d) -> d.fill_opacity)
            .style("stroke-width", (d) -> d.stroke_width)

    block_toggle_select: (grid, e) =>
        if not grid?
            return
        # Toggle selected state of clicked block
        if grid.selected(e.block_id)
            grid.deselect_block(e.d)
        else
            grid.select_block(e.d)

    update_selected: () =>
        ids = if @grids.a? then @grids.a.selected_block_ids() else []
        ids = ids.concat(if @grids.b? then @grids.b.selected_block_ids() else [])
        @select_blocks_by_id(ids).classed('selected', true)

    # UI update
    highlight_comparison: () =>
        try
            c = @compare()
            @select_blocks_by_id(Object.keys(c.different))
                .classed('different', true)
                .classed('same', false)
            @select_blocks_by_id(Object.keys(c.same))
                .classed('same', true)
                .classed('different', false)
        catch e
            (->)


class PlacementComparator extends BasePlacementComparator
    ###
    # This class requires a `PlaceContext` to be provided when resetting a
    # grid.  Each `PlaceContext` contains the netlist info required to look-up
    # block-net connectivity information.  This place context is then passed
    # along to create a `ControllerPlacementGrid` instance for the
    # corresponding grid, rather than a `PlacementGrid`.  The
    # `ControllerPlacementGrid` uses the place context to highlight the nets
    # connected to any blocks in the grid that are either selected or hovered.
    ###
    reset_grid_a: (place_context) =>
        @grid_containers.a.html('')
        @grids.a = new ControllerPlacementGrid(place_context, @grid_containers.a)
        @_connect_grid_signals(@grids.a)
        if @grids.b?
            @grids.b.set_zoom([0, 0], 1, false)

    reset_grid_b: (place_context) =>
        @grid_containers.b.html('')
        @grids.b = new ControllerPlacementGrid(place_context, @grid_containers.b)
        @_connect_grid_signals(@grids.b)
        if @grids.a?
            @grids.a.set_zoom([0, 0], 1, false)

    _connect_grid_signals: (grid) =>
        super grid

        # Connect signals for updating net-related hover activity.
        $(grid).on("block_mouseover", (e) =>
            if @grids.a?
                if e.grid == @grids.b
                    e.block.rect(@grids.a)
                        .classed('net_hovered', true)
                    @grids.a.set_selected_nets()
            if @grids.b?
                if e.grid == @grids.a
                    e.block.rect(@grids.b)
                        .classed('net_hovered', true)
                    @grids.b.set_selected_nets()
        )
        $(grid).on("block_mouseout", (e) =>
            if @grids.b? and e.grid == @grids.a
                e.block.rect(@grids.b)
                    .classed('net_hovered', false)
                @grids.b.set_selected_nets()
            if @grids.a? and e.grid == @grids.b
                e.block.rect(@grids.a)
                    .classed('net_hovered', false)
                @grids.a.set_selected_nets()
        )

    update_selected: () =>
        super()

        for label in ['a', 'b']
            if @grids[label]?
                @grids[label].set_selected_nets()

@BasePlacementComparator = BasePlacementComparator
@PlacementComparator = PlacementComparator
