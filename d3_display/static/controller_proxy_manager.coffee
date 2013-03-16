class ControllerProxyManager
    constructor: () ->
        @controllers = {}

    add: (process_id, controller) =>
        @controllers[process_id] = controller
        obj = @
        process_info = process_id: process_id, controller: controller
        $(obj).trigger(type: "controller_added", process_id: process_id, controller: controller)

    remove: (process_id) =>
        delete @controllers[process_id]
        obj = @
        $(obj).trigger(type: "controller_removed", process_id: process_id)

    controller_list: () => (process_id: k, controller: v for k,v of @controllers)

@ControllerProxyManager = ControllerProxyManager
