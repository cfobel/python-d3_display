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
        @place_context = null
        @_initialized = false

        obj = @

        $(obj).on("iteration_completed", (e) =>
            obj.set_iteration_indexes(e.outer_i, e.inner_i)
            obj.update_iteration_count()
        )
        $(obj).on("iteration_pending", (e) =>
            obj.update_iteration_count()
        )
        $(obj).on("config_updated", (e) =>
            obj.update_config()
        )
        @get_config()
        @initialize()

    get_config: (on_response=null) =>
        obj = @
        _on_response = (response) =>
            #console.log("get_config", response)
            response.command = 'config_dict'
            config = response.result
            if config.netlist_file?
                @config.netlist_path = config.netlist_file
            if config.arch_file?
                @config.arch_path = config.arch_file
            if config.placer_opts?
                @config.placer_opts = config.placer_opts
            if not @outer_i?
                # Outer iteration index is not set, so force initialization
                @sync_iteration_indexes(@update_iteration_count)
            if on_response?
                on_response(response)
            data =
                type: "config_updated"
                response: response
                config: response.result
            $(obj).trigger(data)
        @do_request({"command": "config_dict"}, (() ->), _on_response)

    set_iteration_indexes: (outer_i, inner_i) =>
        @outer_i = outer_i
        @inner_i = inner_i

    sync_iteration_indexes: (on_completed=null) =>
        @get_outer_i((response) =>
            #console.log("sync_iteration_indexes", "get_outer_i", response)
            @outer_i = response
            @get_inner_i((response) =>
                #console.log("sync_iteration_indexes", "get_inner_i", response)
                @inner_i = response
                if on_completed?
                    on_completed({outer_i: @outer_i, inner_i: @inner_i})
            )
        )

    get_inner_i: (on_response=null) =>
        @do_command({"command": "iter__inner_i"}, on_response)

    get_outer_i: (on_response=null) =>
        @do_command({"command": "iter__outer_i"}, on_response)

    initialize: () =>
        obj = @
        if not @_initialized
            obj.get_block_net_counts((result) =>
                obj.block_net_counts = result
                obj.get_net_to_block_id_list((result) =>
                    obj.net_to_block_ids = result
                    obj.get_block_to_net_ids((result) =>
                        obj.block_to_net_ids = result
                        obj.place_context = new PlaceContext(obj.net_to_block_ids, obj.block_to_net_ids, obj.block_net_counts)
                        @sync_iteration_indexes(() =>
                            if @outer_i?
                                @_initialized = true
                            else
                                obj.do_command({"command": "initialize", "kwargs": {"depth": 2}}, (value) =>
                                    obj.do_iteration((value) =>
                                        obj.do_iteration((value) =>
                                            @_initialized = true
                                        )
                                    )
                                )
                        )
                    )
                )
            )

    update_config: () =>
        @row().find('td.netlist')
            .html(coffee_helpers.split_last(@config.netlist_path, '/'))
            .attr("title", @config.netlist_path)
        @row().find('td.seed').html(@config.placer_opts.seed)

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

    process_status_update: (message) =>
        obj = @
        message = @deserialize(message)
        if 'async_id' of message
            if @pending_requests[message.async_id]?
                @pending_requests[message.async_id](message)
                $(obj).trigger(type: "async_response", controller: obj, response: message)

    do_command: (command_config, on_response) =>
        _on_response = (controller, async_response) =>
           on_response(async_response.result)
        obj = @
        @do_request(command_config, (() ->), (response) =>
            _on_response(obj, response)
        )

    get_block_to_net_ids: (on_response) =>
        @do_command({"command": "block_to_net_ids"}, on_response)

    get_block_net_counts: (on_response) =>
        @do_command({"command": "block_net_counts"}, on_response)

    get_net_to_block_id_list: (on_response) =>
        @do_command({"command": "net_to_block_id_list"}, on_response)

    get_block_positions: (on_response) =>
        @do_command({"command": "get_block_positions"}, on_response)

    do_iteration: (on_response=null) =>
        obj = @
        _on_ack = (ack_response) =>
            # Add iteration command key for counting the number of
            # outstanding iterations to be done.
            @pending_iterations[ack_response.async_id] = null
            $(obj).trigger(type: "iteration_pending")
        _on_response = (async_response) =>
            if async_response.async_id of @pending_iterations
                delete @pending_iterations[async_response.async_id]
            if on_response?
                on_response(async_response)
            data =
                type: "iteration_completed"
                response: async_response
                outer_i: async_response.outer_i
                inner_i: async_response.inner_i
                next_outer_i: async_response.result[0]
                next_inner_i: async_response.result[1]
            $(obj).trigger(data)
        @do_request({"command": "iter__next"}, _on_ack, _on_response)

    do_request: (message, on_ack, on_response=null) =>
        _on_ack = (message) =>
            if 'async_id' of message
                @pending_requests[message.async_id] = on_response
            on_ack(message)

        super message, _on_ack

@ControllerProxy = ControllerProxy
