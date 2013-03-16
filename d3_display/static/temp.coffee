# Swappable Mixins in CoffeeScript
# ================================

# Many thanks to Hashmal, who wrote this to start.
# https://gist.github.com/803816/aceed8fc57188c3a19ce2eccdb25acb64f2be94e

# Usage
# -----

# class Derp extends Mixin
#  setup: ->
#    @googly = "eyes"

#  derp: ->
#    alert "Herp derp! What's with your #{ @googly }?"

# class Herp
#  constructor: ->
#    Derp::augment this

# herp = new Herp
# herp.derp()

# Mixin
# -----

# Classes inheriting `Mixin` will become removable mixins, enabling you to
# swap them around.

class Mixin

  # "Class method". Augment object or class `t` with new methods.
  augment: (t) ->
    (t[n] = m unless n == 'augment' or !this[n].prototype?) for n, m of this
    t.setup()

  # When an object is augmented with at least one mixin, call this method to
  # remove `mixin`.
  eject: (mixin) ->
    (delete this[n] if m in (p for o, p of mixin::)) for n, m of this

  # Implement in your mixin to act as a constructor for mixed-in properties
  setup: ->

# Limitations
# -----------

# * When a class is augmented, all instances of that class are augmented too,
#   and when a mixin is ejected from a class, all instances lose that mixin
#   too.
# * You can't eject a mixin from an object if that mixin was added to the
#   object's class. Eject the mixin from the class instead.

@Mixin = Mixin
class EchoController
    constructor: (@context, @uri) ->
        @last_response = null

    send: (sock, message) -> sock.send(message)

    serialize: (message) -> message

    deserialize: (message) -> message

    do_request: (message, on_recv) =>
        try
            sock = @context.socket(nullmq.REQ)
            sock.connect(@uri)
            @send(sock, @serialize(message))
            obj = @
            _on_recv = (value) ->
                value = obj.deserialize(value)
                on_recv(value)
            sock.recv(_on_recv)
        catch error
            alert(error)


class EchoJsonController extends EchoController
    serialize: (javascript_obj) -> JSON.stringify(javascript_obj)

    deserialize: (json_string) ->
        try
            value = JSON.parse(json_string)
        catch error
            alert(error)
            value = null
        return value


@EchoController = EchoController
@EchoJsonController = EchoJsonController
class ControllerFactoryProxy extends EchoJsonController
    constructor: (@context, @action_uri) ->
        @hostname = @action_uri.split(':')[1][2..]
        super @context, @action_uri

    reset: () =>
        obj = @
        obj.do_request(command: "available_netlists", (value) =>
            @netlists = value.result
            obj.do_request(command: "available_architectures",
                (value) =>
                    @architectures = value.result
                    obj.do_request(command: "available_modifier_names", (value) =>
                        @modifier_names = value.result
                        obj.do_request(command: "running_processes", (value) =>
                            for process_info in value.result
                                data = $().extend({type: "controller"}, process_info)
                                data.uris.rep = data.uris.rep.replace('*', obj.hostname)
                                data.uris.pub = data.uris.pub.replace('*', obj.hostname)
                                $(obj).trigger(data)
                            event_data =
                                type: "reset_completed"
                                controller_factory: obj
                                running_processes: value.result
                            $(obj).trigger(event_data)
                        )
                    )
            )
        )

    make_controller: (netlist, arch, modifier_class) =>
        obj = @
        kwargs =
            modifier_class: modifier_class
            netlist_path: netlist
            arch_path: arch
            auto_run: true
        this.do_request({command: "make_controller", kwargs: kwargs}, (value) =>
            if 'error' in value.result
                console.log(error: value.result.error, response: value)
            else
                data = $().extend({type: "controller"}, kwargs)
                data = $().extend(data, value.result)
                data.uris.rep = data.uris.rep.replace('*', obj.hostname)
                data.uris.pub = data.uris.pub.replace('*', obj.hostname)
                $(obj).trigger(data)
        )

@ControllerFactoryProxy = ControllerFactoryProxy
class ControllerProxy extends EchoJsonController
    constructor: (@context, @rep_uri, @pub_uri, @config) ->
        super @context, @rep_uri
        @socks =
            rep: @echo_fe
            sub: @context.socket(nullmq.SUB)
        @socks.sub.connect(@pub_uri)
        @socks.sub.setsockopt(nullmq.SUBSCRIBE, "")
        @socks.sub.recvall(@process_status_update)
        @pending_requests = {}
        @pending_iterations = {}
        @pending_config = {}
        @pending_outer_i = {}
        @pending_inner_i = {}
        @pending_block_positions = {}
        @pending_net_to_block_id_list = {}

        @outer_i = null
        @inner_i = null
        @net_to_block_ids = null
        @block_to_net_ids = null
        @block_net_counts = null
        @_initialized = false
        @_initializing = false

        obj = @

        $(obj).on("async_response", (e) =>
            @process_async_response(e.response)
        )
        $(obj).on("iteration_completed", (e) =>
            obj.set_iteration_indexes(e.outer_i, e.inner_i)
            obj.update_iteration_count()
        )
        $(obj).on("iteration_update", (e) =>
            #console.log("iteration_update", e, e.response.outer_i, e.response.inner_i)
            obj.set_iteration_indexes(e.response.outer_i, e.response.inner_i)
            obj.update_iteration_count()
        )
        $(obj).on("config_updated", (e) =>
            if 'netlist_file' of e.config
                @config.netlist_path = e.config.netlist_file
            if 'arch_file' of e.config
                @config.arch_path = e.config.arch_file
            obj.update_config()
        )

        @do_request({"command": "config_dict"}, (value) =>
            # This will force initialization, if necessary
            @sync_iteration_indexes()
        )

    set_iteration_indexes: (outer_i, inner_i) =>
        if outer_i != null and not @_initialized
            console.log("initialized", @config.process_id)
            @_initialized = true
        @outer_i = outer_i
        @inner_i = inner_i

    sync_iteration_indexes: () =>
        obj = @
        obj.do_request({"command": "iter__outer_i"}, (value) =>
            obj.do_request({"command": "iter__inner_i"}, (value) =>)
        )

    initialize: (force=false) =>
        obj = @
        if force or not @_initialized and not @_initializing
            @_initializing = true
            #console.log("initialize")
            obj.do_request({"command": "initialize", "kwargs": {"depth": 2}}, (value) =>
                obj.do_request({"command": "iter__next"}, (value) =>
                    obj.do_request({"command": "iter__next"}, (value) =>
                        @_initializing = false
                    )
                )
            )

    update_config: () =>
        @row().find('td.netlist')
            .html(coffee_helpers.split_last(@config.netlist_path, '/'))
            .attr("title", @config.netlist_path)

    update_iteration_count: () =>
        remaining = Object.keys(@pending_iterations).length
        if remaining > 0
            remaining_text = " (" + remaining + ")"
        else
            remaining_text = ""
        class_ = "iteration" + (if remaining then " alert alert-info" else "")
        @row().find('td.iteration')
            .attr("class", class_)
            .html(
                if @outer_i? and @inner_i?
                    @outer_i + ", " + @inner_i + remaining_text
                else
                    "initializing..." + remaining_text
            )

    row: () => 
        $('#id_controllers_tbody > tr.controller_row[data-id="' + @config.process_id + '"]')

    process_async_response: (message) =>
        obj = @
        ###
        if not ('command' of message) or message.command != 'swap_info'
            console.log("process_async_response", message)
        ###
        if 'command' of message and message.command == 'iter__next'
            data =
                type: "iteration_completed"
                response: message
                outer_i: message.outer_i
                inner_i: message.inner_i
                next_outer_i: message.result[0]
                next_inner_i: message.result[1]
            $(obj).trigger(data)
        if 'command' of message and message.command in ['iter__outer_i', 'iter__inner_i']
            #console.log("process_async_response->outer/inner_i", message, ('error' of message))
            if ('error' of message) or message.outer_i == null
                @initialize()
            else
                data =
                    type: "iteration_update"
                    response: message
                    outer_i: message.outer_i
                    inner_i: message.inner_i
                $(obj).trigger(data)
        else if 'command' of message and message.command == 'config_dict'
            data =
                type: "config_updated"
                response: message
                config: message.result
            $(obj).trigger(data)

    process_status_update: (message) =>
        obj = @
        message = @deserialize(message)
        if 'async_id' of message
            if message.async_id of @pending_config
                delete @pending_config[message.async_id]
            if message.async_id of @pending_outer_i
                delete @pending_outer_i[message.async_id]
                message.command = 'iter__outer_i'
            if message.async_id of @pending_inner_i
                delete @pending_inner_i[message.async_id]
                message.command = 'iter__inner_i'
            if message.async_id of @pending_iterations
                delete @pending_iterations[message.async_id]
            if message.async_id of @pending_block_positions
                on_recv = @pending_block_positions[message.async_id]
                delete @pending_block_positions[message.async_id]
                on_recv(message.result)
            if message.async_id of @pending_requests
                on_response = @pending_config[message.async_id]
                if on_response?
                    on_response(obj, message)
                delete @pending_requests[message.async_id]
                $(obj).trigger(type: "async_response", controller: obj, response: message)

    get_net_to_block_id_list: (on_response) =>
        _on_response = (controller, async_response) =>
           async_response.testing = 'net_to_block_id_list'
           on_response(async_response)

        on_ack = (async_ack) =>
            @pending_net_to_block_id_list[async_ack.async_id] = _on_response

        @do_request({"command": "net_to_block_id_list"}, on_ack)

    get_block_positions: (on_recv) =>
        @do_request({"command": "get_block_positions"}, (async_response) =>
            @pending_block_positions[async_response.async_id] = on_recv
        )

    do_request: (message, on_ack, on_response=null) =>
        _on_ack = (message) =>
            if 'async_id' of message
                @pending_requests[message.async_id] = on_response
                if 'command' of message and message.command == 'iter__next'
                    @pending_iterations[message.async_id] = on_response
                if 'command' of message and message.command == 'config_dict'
                    @pending_config[message.async_id] = on_response
                if message.command? and message.command == 'outer_i'
                    @pending_outer_i[message.async_id] = on_response
                if message.command? and message.command == 'inner_i'
                    @pending_inner_i[message.async_id] = on_response
            on_ack(message)

        super message, _on_ack

@ControllerProxy = ControllerProxy
class ControllerProxyManager
    constructor: () ->
        @controllers = {}

    add: (process_id, controller) =>
        @controllers[process_id] = controller
        obj = @
        process_info = process_id: process_id, controller: controller
        c = new PlacementCollector([process_info])

        c.collect('get_net_to_block_id_list', (results) =>
            controller.net_to_block_ids = results[0].result
            #c.collect('block_to_net_ids', (results) =>
                #controller.block_to_net_ids = results[0]
                #c.collect('block_net_counts', (results) =>
                    #controller.block_net_counts = results[0]
            $(obj).trigger(type: "controller_added", process_id: process_id, controller: controller)
                #)
            #)
        )

    remove: (process_id) =>
        delete @controllers[process_id]
        obj = @
        $(obj).trigger(type: "controller_removed", process_id: process_id)

    controller_list: () => (process_id: k, controller: v for k,v of @controllers)

@ControllerProxyManager = ControllerProxyManager
class PlacementCollector
    constructor: (@process_infos) ->
        @_on_recv = null
        @finished = false
        @results = []

    _handle_response: (process_info, value) =>
        data = $().extend(process_info, {result: value})
        @results.push(data)
        if @results.length >= @process_infos.length
            # We've received all requested results, so call `on_recv`
            if @_on_recv?
                @_on_recv(@results)
                @finished = true

    collect: (function_name, on_recv) =>
        @finished = false
        @results = []
        @_on_recv = on_recv
        for info in @process_infos
            info.controller[function_name]((value) => @_handle_response(info, value))

@PlacementCollector = PlacementCollector
class PlacementComparator
    constructor: (@grid_a_container, @grid_b_container) ->
        @grid_a_container.html('')
        @grid_a = new PlacementGrid(@grid_a_container.attr("id"))
        @grid_a_container.style("border", "solid #9e6ab8")

        @grid_b_container.html('')
        @grid_b = new PlacementGrid(@grid_b_container.attr("id"))
        @grid_b_container.style("border", "solid #7bb33d")

        obj = @

        for grid in [@grid_a, @grid_b]
            $(grid).on("block_mouseover", (e) =>
                @block_emphasize(@grid_a, e.block)
                @block_emphasize(@grid_b, e.block)
            )
            $(grid).on("block_mouseout", (e) =>
                @block_deemphasize(@grid_a, e.block)
                @block_deemphasize(@grid_b, e.block)
            )
            $(grid).on("block_click", (e) =>
                @block_toggle_select(@grid_a, e)
                @block_toggle_select(@grid_b, e)
            ) 
        $(obj.grid_a).on("zoom_updated", (e) ->
            # When zoom is updated on grid a, update grid b to match.
            # N.B. We must set `signal=false`, since otherwise we would end up
            # in an endless ping-pong back-and-forth between the two grids.
            obj.grid_b.set_zoom(e.translate, e.scale, false)
        )

        $(obj.grid_b).on("zoom_updated", (e) ->
            # When zoom is updated on grid b, update grid a to match.
            # N.B. We must set `signal=false`, since otherwise we would end up
            # in an endless ping-pong back-and-forth between the two grids.
            obj.grid_a.set_zoom(e.translate, e.scale, false)
        )

    block_emphasize: (grid, block) -> block.rect(grid).style("fill-opacity", 1.0)

    block_deemphasize: (grid, block) ->
        block.rect(grid).style("fill-opacity", (d) -> d.fill_opacity)
            .style("stroke-width", (d) -> d.stroke_width)

    block_toggle_select: (grid, e) ->
        # Toggle selected state of clicked block
        if grid.selected(e.block_id)
            grid.deselect_block(e.d)
        else
            grid.select_block(e.d)


@PlacementComparator = PlacementComparator
class Block
    constructor: (@id) ->
    rect_id: () => "block_" + @id
    rect: (grid) => d3.select("#" + grid.grid_container.attr("id") + " ." + @rect_id())


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


class PlacementGrid
    constructor: (@id, @width=null) ->
        @zoom = d3.behavior.zoom()
        @grid_container = d3.select('#' + @id)
        @header = d3.select('#' + @id)
                  .append('div')
                    .attr('class', 'grid_header')
        if not @width?
            @width = @grid_container.style("width")
            result = /(\d+(\.\d+))px/.exec(@width)
            if result
                @width = +result[1]
            console.log("PlacementGrid", "inferred width", @width)
        @width /= 1.15
        @grid = d3.select("#" + @id)
                    .append("svg")
                        .attr("width", 1.1 * @width)
                        .attr("height", 1.1 * @width)
                    .append('svg:g')
                        .attr("id", @id + "_transform_group")
                        .call(@zoom.on("zoom", () => @update_zoom()))
                    .append('svg:g')
                        .attr("class", "chart")
        zoom = window.location.hash
        result = /#translate\((-?\d+\.\d+),(-?\d+\.\d+)\)\s+scale\((-?\d+\.\d+)\)/.exec(zoom)
        if result and result.length == 4
            [translate_x, translate_y, scale] = result[1..]
            console.log(result)
            @zoom.scale(scale)
            @zoom.translate([translate_x, translate_y])
            @update_zoom()
        else
            console.log(zoom)
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
        #_.templateSettings =
          #interpolate: /\{\{(.+?)\}\}/g
        #@template_text = d3.select("#placement_info_template").html()
        #@template = _.template(@template_text)
        #@selected_container = d3.select("#placement_info_selected")
        @block_positions = null
        @swap_infos = new Array()

    update_block_info: (block) =>
        @header.datum(block)
            .html((d) -> @block_info_template(d))

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
            $(obj).trigger(type: "zoom_updated", translate: translate, scale: scale)

    set_zoom_location: () =>
        transform_str = "translate(" + @zoom.translate() + ")" + " scale(" +
            @zoom.scale() + ")"
        window.location.hash = transform_str

    selected_fill_color: () -> @colors(@selected_fill_color_num)

    translate_block_positions: (block_positions) ->
        @_last_translated_positions = block_positions
        data = new Array()
        for position, i in block_positions
            item =
                block_id: i
                x: position[0]
                y: position[1]
                z: position[2]
                selected: false
                fill_opacity: 0.5
                stroke_width: 1
            data.push(item)
        @dims.x.max = Math.max(d3.max(item.x for item in data), @dims.x.max)
        @dims.x.min = Math.min(d3.min(item.x for item in data), @dims.x.min)
        @dims.y.max = Math.max(d3.max(item.y for item in data), @dims.y.max)
        @dims.y.min = Math.min(d3.min(item.y for item in data), @dims.y.min)
        for item in data
            if item.x < @dims.x.min + 1 or item.x > @dims.x.max - 1 or item.y < @dims.y.min + 1 or item.y > @dims.y.max - 1
                item.io = true
            else
                item.io = false
        @scale.x.domain([@dims.x.min, @dims.x.max + 1]).range([0, @width])
        @scale.y.domain([@dims.y.min, @dims.y.max + 1]).range([@width, 0])
        return data

    cell_width: () -> @scale.x(1)
    # Scale the height of each cell to the grid vertical height divided by the
    # number of blocks in the y-dimension.  Note that since `@scale.y` is
    # inverted*, we use `@dims.y.max` rather than 1 as the arg to `@scale.y` to
    # get the height of one cell.
    #
    # *see `translate_block_positions`
    cell_height: () -> @scale.y(@dims.y.max)
    block_width: () -> 0.8 * @cell_width()
    block_height: () -> 0.8 * @cell_height()
    block_color: (d) ->
        result = if d.io then @io_fill_color else d.fill_color
        return result
    cell_position: (d) => x: @scale.x(d.y), y: @scale.y(d.x)
    cell_center: (d) =>
        position = @cell_position d
        x: position.x + 0.5 * @cell_width(), y: position.y + 0.5 * @cell_height()

    clear_selection: () ->
        @_selected_blocks = {}
        #@update_selected_block_info()
        # Skip cell formatting until we can verify that it is working as
        # expected.
        #@update_cell_formats()

    select_block: (d) ->
        @_selected_blocks[d.block_id] = null
        #@update_selected_block_info()
        # Skip cell formatting until we can verify that it is working as
        # expected.
        #@update_cell_formats()

    deselect_block: (d) ->
        delete @_selected_blocks[d.block_id]
        #@update_selected_block_info()
        # Skip cell formatting until we can verify that it is working as
        # expected.
        #@update_cell_formats()

    selected_block_ids: () -> +v for v in Object.keys(@_selected_blocks)

    selected: (block_id) -> block_id of @_selected_blocks

    #update_selected_block_info: () ->
        #data = (@block_positions[block_id] for block_id in @selected_block_ids())
        #infos = @selected_container.selectAll(".placement_info")
            #.data(data, (d) -> d.block_id)
        #infos.enter()
          #.append("div")
            #.attr("class", "placement_info")
        #infos.exit().remove()
        #infos.html((d) -> placement_grid.template($().extend({net_ids: ''}, d)))

    set_raw_block_positions: (raw_block_positions) ->
        @set_block_positions(@translate_block_positions(raw_block_positions))

    set_block_positions: (block_positions) ->
        @block_positions = block_positions
        @update_cell_data()
        # Skip cell formatting until we can verify that it is working as
        # expected.
        #@update_cell_formats()
        @update_cell_positions()
        #@update_selected_block_info()

    reset_block_formats: ->
        blocks = @grid.selectAll('.block')
            .style("stroke", '#555')
            .style("fill", "black")
            .style('opacity', 1.0)
            .style('stroke-width', 1.0)

    update_cell_data: () ->
        # Each tag of class `cell` is an SVG group tag.  Each such group
        # contains an SVG rectangle tag, corresponding to a block in the
        # placement grid.
        blocks = @grid.selectAll(".cell")
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
                    $(obj).trigger(type: 'block_click', grid: obj, block: b, block_id: i, d: d)
                )
                .on('mouseout', (d, i) =>
                    b = new Block(i)
                    $(obj).trigger(type: 'block_mouseout', grid: obj, block: b, block_id: i, d: d)
                )
                .on('mouseover', (d, i) =>
                    b = new Block(i)
                    $(obj).trigger(type: 'block_mouseover', grid: obj, block: b, block_id: i, d: d)
                )
                .style("stroke", '#555')
                .style('fill-opacity', (d) -> d.fill_opacity)
                .style('stroke-width', (d) -> d.stroke_width)
                # Center block within cell
                .attr("transform", (d) =>
                    x_padding = (@cell_width() - @block_width()) / 2
                    y_padding = (@cell_height() - @block_height()) / 2
                    "translate(" + x_padding + "," + y_padding + ")")
        # Remove blocks that are no longer in the data set.
        blocks.exit().remove()

    update_cell_positions: () ->
        @grid.selectAll(".cell").transition()
            .duration(600)
            .ease("cubic-in-out")
            .attr("transform", (d) =>
                position = @cell_position d
                "translate(" + position.x + "," + position.y + ")")

    update_cell_formats: () ->
        obj = @
        blocks = @grid.selectAll(".cell").select(".block")
            .style("fill", (d) ->
                if obj.selected(d.block_id)
                    obj.selected_fill_color()
                else
                    obj.block_color(d)
            )
            .style("fill-opacity", (d) ->
                if obj.selected(d.block_id)
                    d.fill_opacity = 0.8
                else
                    d.fill_opacity = 0.5
                return d.fill_opacity
            )
            .style("stroke-width", (d) ->
                if obj.selected(d.block_id)
                    d.stroke_width = 4
                else
                    d.stroke_width = 1
                return d.stroke_width
            )

    highlight_area_range: (a) ->
        area_range_group = d3.select(".chart").append("svg:g")
            .attr("class", "area_range_group")
            .style("opacity", 0.75)
            .append("svg:rect")
            .attr("class", "area_range_outline")
            .attr("width", a.second_extent * @scale.x(1))
            .attr("height", a.first_extent * @scale.y(@dims.y.max))
            .on('mouseover', (d) ->
                d3.select(this).style("stroke-width", 10)
            )
            .on('mouseout', (d) ->
                d3.select(this).style("stroke-width", 7)
            )
            .style("fill", "none")
            .style("stroke", @colors((a.first_index * a.second_index) % 10))
            .style("stroke-width", 7)

        area_range_group.transition()
            .duration(400)
            .ease("cubic-in-out")
            .attr("transform", "translate(" + @scale.x(a.second_index) + ", " + @scale.y(a.first_index + a.first_extent - 1) + ")")


class AreaRange
    constructor: (@first_index, @second_index, @first_extent, @second_extent) ->

    contains: (point) ->
        return (point.x >= @first_index and point.x < @first_index + @first_extent and point.y >= @second_index and point.y < @second_index + @second_extent)


@PlacementGrid = PlacementGrid
@AreaRange = AreaRange
@Block = Block
set_options = (values, dropdown) =>
    dropdown.empty()
    for v in values
        $("<option />", val: v, text: v).appendTo(dropdown)


set_paths = (paths, dropdown) =>
    dropdown.empty()
    for p in paths
        path_components = p.split('/')
        name = path_components[path_components.length - 1]
        $("<option />", val: p, text: name).appendTo(dropdown)


last = (data) -> data[data.length - 1]


split_last = (data, delimiter) -> last(data.split(delimiter))


@coffee_helpers = 
    set_options: set_options
    set_paths: set_paths
    last: last
    split_last: split_last
