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

    make_controller: (netlist, arch, modifier_class, seed=null) =>
        obj = @
        kwargs =
            modifier_class: modifier_class
            netlist_path: netlist
            arch_path: arch
            seed: seed
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

    terminate: (process_id, on_terminated=null) =>
        terminate_data =
            command: 'terminate_process'
            kwargs:
                process_id: process_id
        @do_request(terminate_data, on_terminated ? (() ->))

@ControllerFactoryProxy = ControllerFactoryProxy
