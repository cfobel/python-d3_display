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


json_compare = (a, b) ->
    [a, b] = (JSON.stringify(v) for v in [a, b])
    return a == b


@coffee_helpers =
    set_options: set_options
    set_paths: set_paths
    last: last
    split_last: split_last
    json_compare: json_compare
    Curve: Curve
