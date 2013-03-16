class StopIteration
    exception_type: 'StopIteration'
    constructor: (@iterator) ->


class SwapGenerator
    constructor: (p, @maps) ->
        @swap_order = Object.keys(@maps.b)
        @count = Math.min(@swap_order.length)

        # Make a copy of parent as a starting point
        @_starting_p = $.extend(true, [], p)
        @reset()

    reset: () ->
        # Make a copy of parent as a starting point
        @p = $.extend(true, [], @_starting_p)
        # Make a local copy of the from_map since we will be modifying it
        @map = $.extend(true, {}, @maps.a)
        @i = 0

    next: () ->
        obj = @
        if @i >= @count
            throw new StopIteration(obj)

        key = @swap_order[@i]
        swap = source: @map[key], target: @maps.b[key]
        if swap.source == swap.target
            # This swap is unnecessary, so skip to the next one
            @i += 1
            return @next()
        else
            if @p[swap.target] of @map
                @map[@p[swap.target]] = swap.source
            [@p[swap.source], @p[swap.target]] = [@p[swap.target], @p[swap.source]]
            @i += 1
            @swap = swap
            return @swap


do_swaps = (p, maps, count=null) ->
    s = new SwapGenerator(p, maps)
    count = count ? s.swap_order.length
    if count > 0
        try
            for i in [0..count - 1]
                swap = s.next()
        catch e
            if not e.exception_type? or e.exception_type != 'StopIteration'
                throw e
    return s.p


get_swaps = (p, maps) ->
    s = new SwapGenerator(p, maps)
    count = count ? s.swap_order.length
    swaps = []
    if count > 0
        try
            for i in [0..count - 1]
                swap = s.next()
                swaps.push(swap)
        catch e
            if not e.exception_type? or e.exception_type != 'StopIteration'
                throw e
    return swaps


class ConfinedSwapCrossover
    constructor: (a, b) ->
        @p =
            a: a
            b: b
        @maps = a: {}, b: {}

        opposite = a: 'b', b: 'a'

        for label in ['a', 'b']
            for id, pos in @p[label]
                if id >= 0 and @p[opposite[label]][pos] != id
                    @maps[label][id] = pos

    do_swaps: (count=null) ->
        do_swaps(@p.a, @maps, count)


@do_swaps = do_swaps
@get_swaps = get_swaps
@SwapGenerator = SwapGenerator
@ConfinedSwapCrossover = ConfinedSwapCrossover
