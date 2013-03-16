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
