class Block
    constructor: (@id) ->
    rect_id: () => "block_" + @id
    rect: (grid) => grid.grid_container.select(" ." + @rect_id())


class Net
    constructor: (@net_id, @block_ids) ->
        @cardinality = @block_ids.length


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


translate_block_positions = (block_positions) ->
    data = new Array()
    for position, i in block_positions
        item =
            block_id: i
            x: position[0]
            y: position[1]
            z: position[2]
            selected: false
        data.push(item)
    return data


class PlacementGrid
    constructor: (@grid_container, @width=null) ->
        @zoom = d3.behavior.zoom()
        #console.log('[PlacementGrid.constructor]', @grid_container, @width)
        @header = @grid_container.append('div')
            .attr('class', 'grid_header')
        if not @width?
            obj = @
            jq_obj = $(obj.grid_container[0])
            # Restrict height to fit within viewport
            width = jq_obj.width()
            height = $(window).height() - jq_obj.position().top - 130
            @width = Math.min(width, height)
            #console.log("PlacementGrid", "inferred width", @width)
        @width /= 1.15

        # Create SVG element for canvas
        @canvas = @grid_container.append("svg")
            .attr("width", 1.1 * @width)
            .attr("height", 1.1 * @width)

        # Add a background rectangle to catch any zoom/pan events that are not
        # caught by any upper layers that are not caught by any upper layers
        @canvas.append('svg:rect')
            .classed('grid_background', true)
            .attr("width", 1.1 * @width)
            .attr("height", 1.1 * @width)
            .call(@zoom.on("zoom", () => @update_zoom()))

        # Catch any zoom/pan events over grid elements.
        @grid = @canvas.append('svg:g')
            .attr('class', '_transform_group')
            .call(@zoom.on("zoom", () => @update_zoom()))
          .append('g')
            .attr('class', 'grid')

        @blocks = @grid.append('svg:g')
            .attr("class", "blocks")

        @area_ranges = @grid.append('svg:g')
            .attr("class", "area_ranges")

        zoom = window.location.hash
        result = /#translate\((-?\d+\.\d+),(-?\d+\.\d+)\)\s+scale\((-?\d+\.\d+)\)/.exec(zoom)
        if result and result.length == 4
            [translate_x, translate_y, scale] = result[1..]
            @zoom.scale(scale)
            @zoom.translate([translate_x, translate_y])
            @update_zoom()
        @scale =
            x: d3.scale.linear()
            y: d3.scale.linear()
        @dims =
            x:
                min: 1000000
                max: -1
            y:
                min: 1000000
                max: -1
        @colors = d3.scale.category10().domain(d3.range(10))
        @selected_fill_color_num = 8
        @io_fill_color = @colors(1)
        @clb_fill_color = @colors(9)
        @_selected_blocks = {}
        @block_positions = null
        @swap_infos = new Array()

        @templates = @get_templates()

        obj = @

        $(obj).on('block_mouseover', (e) => @update_header(e.block))
        $(obj).on('block_click', (e) ->
            if not e.d.selected
                d3.select(e.rect).classed('selected', true)
                obj.select_block(e.d)
                e.d.selected = true
                response = $().extend({}, e)
                response.type = 'block_selected'
                $(obj).trigger(response)
            else
                d3.select(e.rect).classed('selected', true)
                obj.deselect_block(e.d)
                e.d.selected = false
                response = $().extend({}, e)
                response.type = 'block_deselected'
                $(obj).trigger(response)
        )

    get_templates: () ->
        _.templateSettings = interpolate: /\{\{(.+?)\}\}/g
        template_texts =
            grid_header: d3.select('.grid_header_template').html()
        templates = {}
        for k, v of template_texts
            templates[k] = _.template(v)
        return templates

    template_context: (d) => block: d, position: @block_positions[d.id]

    update_header: (block) =>
        obj = @
        @header.datum(block)
            .html((d) ->
                try
                    template_context = obj.template_context(d)
                    obj.templates.grid_header(template_context)
                catch e
                    @_last_obj =
                        data: obj
                        block: d
            )

    set_zoom: (translate, scale, signal=true) =>
        @zoom.translate(translate)
        @zoom.scale(scale)
        @update_zoom(signal)

    update_zoom: (signal=true) =>
        @_update_zoom(@zoom.translate(), @zoom.scale(), signal)

    _update_zoom: (translate, scale, signal=true) =>
        transform_str = "translate(" + translate + ")" + " scale(" + scale + ")"
        @grid.attr("transform", transform_str)
        if signal
            obj = @
            $(obj).trigger(type: "zoom_updated", grid: obj, translate: translate, scale: scale)

    set_zoom_location: () =>
        transform_str = "translate(" + @zoom.translate() + ")" + " scale(" +
            @zoom.scale() + ")"
        window.location.hash = transform_str

    selected_fill_color: () -> @colors(@selected_fill_color_num)

    cell_width: () -> @scale.x(1)
    # Scale the height of each cell to the grid vertical height divided by the
    # number of blocks in the y-dimension.  Note that since `@scale.y` is
    # inverted*, we use `@dims.y.max` rather than 1 as the arg to `@scale.y` to
    # get the height of one cell.
    #
    # *see `translate_block_positions`
    cell_height: () -> @scale.y(@dims.y.max)
    block_width: () -> 0.7 * @cell_width()
    block_height: () -> 0.7 * @cell_height()
    cell_position: (d) => x: @scale.x(d.y), y: @scale.y(d.x)
    cell_center: (d) =>
        position = @cell_position d
        x: position.x + 0.5 * @cell_width(), y: position.y + 0.5 * @cell_height()

    clear_selection: () =>
        for block_id, none of @_selected_blocks
            @deselect_block(@block_positions[block_id])

    select_block: (d) ->
        @_selected_blocks[d.block_id] = null

    deselect_block: (d) ->
        delete @_selected_blocks[d.block_id]

    selected_block_ids: () -> +v for v in Object.keys(@_selected_blocks)

    selected: (block_id) -> block_id of @_selected_blocks

    update_selected_block_info: () ->
        data = (@block_positions[block_id] for block_id in @selected_block_ids())
        infos = @selected_container.selectAll(".placement_info")
            .data(data, (d) -> d.block_id)
        infos.enter()
          .append("div")
            .attr("class", "placement_info")
        infos.exit().remove()
        infos.html((d) -> placement_grid.template($().extend({net_ids: ''}, d)))

    set_raw_block_positions: (raw_block_positions) ->
        @set_block_positions(translate_block_positions(raw_block_positions))

    set_block_positions: (block_positions) ->
        @dims.x.max = Math.max(d3.max(item.x for item in block_positions), @dims.x.max)
        @dims.x.min = Math.min(d3.min(item.x for item in block_positions), @dims.x.min)
        @dims.y.max = Math.max(d3.max(item.y for item in block_positions), @dims.y.max)
        @dims.y.min = Math.min(d3.min(item.y for item in block_positions), @dims.y.min)

        @scale.x.domain([@dims.x.min, @dims.x.max + 1]).range([0, @width])
        @scale.y.domain([@dims.y.min, @dims.y.max + 1]).range([@width, 0])

        @block_positions = block_positions
        @update_cell_data()
        @update_cell_positions()

    update_cell_data: () ->
        # Each tag of class `cell` is an SVG group tag.  Each such group
        # contains an SVG rectangle tag, corresponding to a block in the
        # placement grid.
        blocks = @blocks.selectAll(".cell")
            .data(@block_positions, (d) -> d.block_id)

        obj = @

        blocks.enter()
            # For block ids that were not previously included in the bound data
            # set, create an SVG group and append an SVG rectangle to it for
            # the block
            .append("svg:g")
                .attr("class", "cell")
            .append("svg:rect")
                .attr("class", (d) -> "block block_" + d.block_id)
                .attr("width", @block_width())
                .attr("height", @block_height())
                .on('click', (d, i) ->
                    b = new Block(i)
                    $(obj).trigger(type: 'block_click', grid: obj, rect: this, block: b, block_id: i, d: d)
                )
                .on('mouseout', (d, i) ->
                    b = new Block(i)
                    b.rect(obj).classed('hovered', false)
                    $(obj).trigger(type: 'block_mouseout', grid: obj, rect: this, block: b, block_id: i, d: d)
                )
                .on('mouseover', (d, i) ->
                    b = new Block(i)
                    b.rect(obj).classed('hovered', true)
                    $(obj).trigger(type: 'block_mouseover', grid: obj, rect: this, block: b, block_id: i, d: d)
                )
                # Center block within cell
                .attr("transform", (d) =>
                    x_padding = (@cell_width() - @block_width()) / 2
                    y_padding = (@cell_height() - @block_height()) / 2
                    "translate(" + x_padding + "," + y_padding + ")")
        # Remove blocks that are no longer in the data set.
        blocks.exit().remove()

    update_cell_positions: () ->
        @blocks.selectAll(".cell").transition()
            .duration(600)
            .ease("cubic-in-out")
            .attr("transform", (d) =>
                position = @cell_position d
                "translate(" + position.x + "," + position.y + ")")

    highlight_area_ranges: (area_ranges) ->
        area_ranges = @area_ranges.selectAll('.area_range')
            .data(area_ranges)
        area_ranges.exit().remove()
        area_ranges.enter().append("svg:rect")
            .attr("class", "area_range")
            .attr("width", (d) => d.second_extent * @scale.x(1))
            .attr("height", (d) => d.first_extent * @scale.y(@dims.y.max))
            .style("stroke", (d) => @colors((d.first_index * d.second_index) % 10))
            .style("fill", "none")
            .style("stroke-width", 7)
            .style('opacity', 0.75)
            .on('mouseover', (d) ->
                d3.select(this).style("stroke-width", 10)
            )
            .on('mouseout', (d) ->
                d3.select(this).style("stroke-width", 7)
            )

        area_ranges.transition()
            .duration(400)
            .ease("cubic-in-out")
            .attr("transform", (d) => "translate(" + @scale.x(d.second_index) + ", " + @scale.y(d.first_index + d.first_extent - 1) + ")")


class ControllerPlacementGrid extends PlacementGrid
    constructor: (@place_context, @grid_container, @width=null) ->
        super @grid_container, @width
        @net_groups = @grid.append('svg:g')
            .attr("class", "net_groups")
        @nets = (@net_by_id(n) for n in [0..@place_context.net_to_block_ids.length - 1])
        obj = @
        $(obj).on('block_mouseover', (e) ->
            d3.select(e.rect).classed('net_hovered', true)
            @set_selected_nets()
        )
        $(obj).on('block_mouseout', (e) =>
            d3.select(e.rect).classed('net_hovered', false)
            @set_selected_nets()
        )
        $(obj).on('block_selected', (e) ->
            @set_selected_nets()
        )

    set_selected_nets: () =>
        rects_to_show_nets_for = @blocks.selectAll('.net_hovered, .selected')[0]
        nets_to_show = {}
        blocks = (d.__data__ for d in rects_to_show_nets_for)
        nets_by_block_id = @nets_by_block_id((b.block_id for b in blocks))
        nets_unmerged = d3.merge((v for k, v of nets_by_block_id))
        nets = _.uniq(nets_unmerged)
        @set_nets(nets)

    set_nets: (nets) =>
        @grid.selectAll('.net_group').remove()
        nets = (n for n in nets when n.cardinality < 10)
        if nets.length <= 0
            return

        obj = @

        target_opacity = null

        net_group = @grid.selectAll('.net_group')
            .data(nets)
          .enter().append('g')
            .classed('net_group', true)
            .style('opacity', (d) ->
                target_opacity = d3.select(this).style('opacity')
                0
            )

        extract_value = (d) =>
            root_coords = obj.cell_center(obj.center_of_gravity(d.net_id))
            target_coords = _.map(obj.block_coords(d.net_id), obj.cell_center)

            ({net_id: d.net_id, target: t, center_of_gravity: root_coords} for t in target_coords)

        net_link = net_group.selectAll('.net_link')
            .data(extract_value, (d) -> JSON.stringify(d))
          .enter().append('line')
            .attr('class', 'net_link')
            .attr("x1", (d) -> d.center_of_gravity.x)
            .attr("y1", (d) -> d.center_of_gravity.y)
            .attr("x2", (d) -> d.target.x)
            .attr("y2", (d) -> d.target.y)

        net_link = net_group.selectAll('.center_of_gravity')
            .data((d) -> [obj.cell_center(obj.center_of_gravity(d.net_id))])
          .enter().append('circle')
            .attr("class", "center_of_gravity")
            .attr("data-net_id", (d) -> d.net_id)
            .attr("cx", (d) -> d.x)
            .attr("cy", (d) -> d.y)
            .attr("r", 8)

        net_group.transition()
            .style('opacity', target_opacity)

    connected_block_ids: (block_id) =>
        try
            connected_block_ids = []
            net_ids = @place_context.block_to_net_ids[block_id]
            for i in [0..@place_context.block_net_counts[block_id] - 1]
                net_id = net_ids[i]
                for b in @place_context.net_to_block_ids[net_id]
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
            nets[b] = (@nets[n] for n in @place_context.block_to_net_ids[b] when n >= 0)
        nets

    map_nets_by_block_id: (block_ids, f) ->
        nets_by_block_id = @nets_by_block_id(block_ids)
        results = []
        for b, nets of nets_by_block_id
            results.push(_.map(nets, f))
        results

    net_by_id: (net_id) =>
        block_ids = @place_context.net_to_block_ids[net_id]
        return new Net(net_id, block_ids)

    select_block_elements_by_ids: (block_ids) =>
        if block_ids.length > 0
            block_element_ids = (".block_" + i for i in block_ids)
            return @blocks.selectAll(block_element_ids.join(","))
        else
            # Empty selection
            return d3.select()

    set_block_positions: (block_positions) =>
        super block_positions
        @set_selected_nets()

    highlight_selected_net_blocks: (net_id) =>
        @grid.selectAll((".block_" + b for b in @nets[net_id].block_ids).join(', '))
            .classed('net_hovered', true)

    unhighlight_selected_net_blocks: (net_id) =>
        @grid.selectAll((".block_" + b for b in @nets[net_id].block_ids).join(', '))
            .classed('net_hovered', false)

    block_coords: (net_id) =>
        coords = []
        for b in @nets[net_id].block_ids
            p = @block_positions[b]
            coords.push(x: p.x, y: p.y)
        coords

    center_of_gravity: (net_id) ->
        x_sum = 0
        y_sum = 0
        coords = @block_coords(net_id)
        for c in coords
            x_sum += c.x
            y_sum += c.y
        x: x_sum / coords.length, y: y_sum / coords.length



class AreaRange
    constructor: (@first_index, @second_index, @first_extent, @second_extent) ->

    contains: (point) ->
        return (point.x >= @first_index and point.x < @first_index + @first_extent and point.y >= @second_index and point.y < @second_index + @second_extent)


AreaRange.from_array = (indices) ->
    new AreaRange(indices[0], indices[1], indices[2], indices[3])


@PlacementGrid = PlacementGrid
@ControllerPlacementGrid = ControllerPlacementGrid
@AreaRange = AreaRange
@Block = Block
@translate_block_positions = translate_block_positions
