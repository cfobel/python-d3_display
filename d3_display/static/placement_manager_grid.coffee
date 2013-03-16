class PlacementManagerGrid extends PlacementGrid
    constructor: (@placement_manager, @grid_container, @width=null) ->
        super @grid_container, @width

        obj = @

        @manager_header = @grid_container.insert('div', '.grid_header')
            .attr('class', 'manager_header')
            .html(@templates.manager_header())

        @manager_header_element = $(obj.manager_header[0])

        @manager_header.select('.swaps_show')
            .on('click', () ->
                obj.swaps_show($(this).prop('checked'))
            )

        @manager_header.select('.swaps_apply')
            .on('click', () ->
                obj.swaps_apply($(this).prop('checked'))
            )

        @manager_header.select('.area_ranges_show')
            .on('click', () ->
                obj.area_ranges_show($(this).prop('checked'))
            )

        @manager_header.select('.refresh_keys')
            .on('click', @refresh_keys)

        @manager_header.select('.select_key')
            .on('click', (d) ->
                key_chooser = obj.manager_header_element.find('.manager_key_options')
                key = obj.keys[key_chooser.val()]
                console.log('[select_key] on.click', d, key_chooser, key)
                obj.select_key(outer_i: key[0], inner_i: key[1] ? 0)
            )

        @keys = {}
        @selected_key = null
        @_swap_contexts = {}
        @_placements = {}
        @_place_configs = {}

        $(obj).on('keys_updated', (e) ->
            key_chooser = obj.manager_header_element.find('.manager_key_options')
            console.log('keys_updated', e, key_chooser)
            coffee_helpers.set_options(e.keys, key_chooser)
        )

        $(obj).on('placement_selected', (e) ->
            if obj.selected_key?
                key_str = obj.get_key_str(obj.selected_key)
                current_option = e.grid.manager_header_element.find('option[value="' + key_str + '"]')
                console.log('[select option]', key_str, current_option)
                current_option.prop('selected', true)
            if e.block_positions?
                block_infos = translate_block_positions(e.block_positions)
                obj._placements[e.key] = block_infos
                for prefix, actions of {swaps_: ['apply', 'show'], area_ranges_: ['show']}
                    for action in actions
                        obj[prefix + action](false)
                        obj.manager_header_element.find('.' + prefix + action)
                            .prop('checked', false)
                            .prop('disabled', true)
                try
                    obj.placement_manager.get_place_config(((config) ->
                        obj._place_configs[e.key] = config
                        obj.area_ranges_show(true)
                        obj.manager_header_element.find('.area_ranges_show')
                            .prop('checked', true)
                            .prop('disabled', false)
                    ), e.key.outer_i, e.key.inner_i ? 0)
                catch e
                    console.log('no config available')
        )

        $(obj).on('swap_context_selected', (e) ->
            if e.swap_context?
                console.log('[swap_context_selected]', e)
                obj._swap_contexts[e.key] = e.swap_context
                obj.swaps_show(true)
                obj.manager_header_element.find('.swaps_show')
                    .prop('disabled', false)
                    .prop('checked', true)
                obj.manager_header_element.find('.swaps_apply')
                    .prop('disabled', false)
        )

        @refresh_keys()

    get_key_str: (key) => key.outer_i + ',' + key.inner_i

    get_templates: () ->
        templates = super()
        template_texts =
            manager_header: d3.select('.placement_manager_grid_header_template').html()
        for k, v of template_texts
            templates[k] = _.template(v)
        return templates

    template_context: (d) =>
        data =
            block: d
            position: @block_positions[d.id]
            keys: @keys
            selected_key: @selected_key

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

    refresh_keys: () =>
        ###
        # Request placement keys
        #  * Request swap context keys
        #   * Update local keys list with union of placement keys and swap
        #     context keys
        #   * If no current placement is set, select the placement
        #     corresponding to the first key (if available)
        ###
        obj = @
        @placement_manager.get_placement_keys((placement_keys) =>
            @placement_manager.get_swap_context_keys((swap_context_keys) =>
                keys_dict = {}
                for k in placement_keys
                    keys_dict[k] = k
                for k in swap_context_keys
                    keys_dict[k] = k
                for k, v of keys_dict
                    if not (k of obj.keys)
                        # The current key is not present in our local key list,
                        # so update our list and trigger a notification of the
                        # update.
                        keys = (v for k, v of keys_dict)
                        obj.keys = keys_dict
                        $(obj).trigger(type: "keys_updated", grid: obj, keys: keys)
                        if not obj.selected_key?
                            # No key is currently selected, so select the first
                            # one.
                            key = _.last(keys)
                            key_data = outer_i: key[0], inner_i: key[1] ? 0
                            obj.select_key(key_data)
                        return
                console.log('[refresh_keys]', 'No new keys')
            )
        )

    select_key: (key) ->
        ###
        # When a new key is selected, we must:
        #
        #  * Uncheck and disable `Show swaps` and `Apply swaps` checkboxes
        #  * Request placement
        #   * Update grid with placement
        #   * Update `current_key`
        #   * Request configuration
        #    * If configuration returned, highlight area ranges (if available)
        #    * Request swap context
        #     * Enable `Show swaps` and `Apply swaps` checkboxes
        #     * Show swaps by default:
        #      * Apply swaps formatting (i.e., `swaps_show(true)`)
        #      * Check `Show swaps` checkbox
        ###
        if not key.outer_i?
            key = outer_i: key[0], inner_i: key[1] ? 0
        if JSON.stringify(key) == JSON.stringify(@selected_key)
            # This key was already selected, so do nothing
            return
        obj = @
        obj.placement_manager.get_block_positions(((block_positions) ->
                obj.selected_key = key
                data =
                    type: 'placement_selected'
                    grid: obj
                    key: key
                    block_positions: block_positions
                $(obj).trigger(data)
                obj.placement_manager.get_swap_context(((swap_context) ->
                    data =
                        type: 'swap_context_selected'
                        grid: obj
                        key: key
                        block_positions: block_positions
                        swap_context: swap_context
                    $(obj).trigger(data)
                ), key.outer_i, key.inner_i ? 0)
            ), key.outer_i, key.inner_i ? 0
        )

    swaps_show: (state) =>
        ###
        # state=true (false->true)
        #
        #  * Set swap data
        #  * Apply block formats to grid
        #  * Apply swap-link formats
        #
        #
        # state=false (true->false)
        #
        #  * Remove all swap-related block formatting
        #  * Remove all swap-link elements
        ###
        @swap_links_show(state)
        @swap_blocks_show(state)

    swap_blocks_show: (state) =>
        obj = @
        if @selected_key? and @_swap_contexts[@selected_key]?
            s = @_swap_contexts[@selected_key]
            if state
                s.update_block_formats(obj)
            else
                s.clear_classes(obj)

    swap_links_show: (state) =>
        obj = @
        if @selected_key?
            if state
                s = @_swap_contexts[@selected_key]
                s.update_block_formats(obj)
                s.set_swap_link_data(obj)
                s.update_link_formats(obj)
            else
                obj.grid_container.selectAll('.swap_link').remove()

    swaps_apply: (state) =>
        ###
        # state=true (false->true)
        #
        #  * Update grid block positions to positions after applying swaps from
        #    swap context.
        #
        #
        # state=false (true->false)
        #
        #  * Update grid block positions to positions in the current placement.
        ###
        obj = @
        if @selected_key?
            if state
                s = @_swap_contexts[@selected_key]
                @set_block_positions(s.apply_swaps(@_placements[@selected_key]))
            else
                @set_block_positions(@_placements[@selected_key])
            $(obj).trigger(type: 'swaps_apply_status', state: state)

    area_ranges_show: (state) =>
        obj = @
        if @selected_key?
            if state
                c = @_place_configs[@selected_key]
                @highlight_area_ranges(AreaRange.from_array(a) for a in c.area_ranges)
            else
                @highlight_area_ranges([])

@PlacementManagerGrid = PlacementManagerGrid
