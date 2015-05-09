[[
==README==

Frame-by-Frame Transform Automation Script

Smoothly transforms various parameters across multi-line, frame-by-frame typesets.

Useful for adding smooth transitions to frame-by-frame typesets that cannot be tracked with mocha,
or as a substitute for the stepped \t transforms generated by the Aegisub-Motion.lua script, which
may cause more lag than hard-coded values.

First generate the frame-by-frame typeset that you will be adding the effect to. Find the lines where
you want the effect to begin and the effect to end, and visually typeset them until they look the way
you want them to.

These lines will act as "keyframes", and the automation will modify all the lines in between so that
the appearance of the first line smoothly transitions into the appearance of the last line. Simply
highlight the first line, the last line, and all the lines in between, and run the automation.

It will only affect the tags that are checked in the popup menu when you run the automation. If you wish
to save specific sets of parameters that you would like to run together, you can use the presets manager.
For example, you can go to the presets manager, check all the color tags, and save a preset named "Colors".
The next time you want to transform all the colors, just select "Colors" from the preset dropdown menu.
The "All" preset is included by default and cannot be deleted. If you want a specific preset to be loaded
when you start the script, name it "Default" when you define the preset.

This may be obvious, but this automation only works on one layer or one component of a frame-by-frame
typeset at a time. If you have a frame-by-frame typeset that has two lines per frame, which looks like:

A1
B1
A2
B2
A3
B3
etc.

Then this automation will not work. The lines must be organized as:

A1
A2
A3
etc.
B1
B2
B3
etc.

And you would have to run the automation twice, once on A and once on B. Furthermore, the text of each
line must be exactly the same once all tags are removed. You can have as many tag blocks as you want
in whatever positions you want for the "keyframe" lines (the first and the last). But once the tags are
taken out, the text of the lines must be identical, down to the last space. If you are using ctrl-D or
copy-pasting, this should be a given, but it's worth a warning.

The lines in between can have any tags you want in them. So long as the automation is not transforming
those particular tags, they will be left untouched. If you need the typeset to suddenly turn huge for one
frame, simply uncheck "fscx" and "fscy" when you run the automation, and the size of the line won't be
touched.

If you are transforming rotations, there is something to watch out for. If you want a line to start
with \frz10 and rotate to \frz350, then with default options, the line will rotate 340 degrees around the
circle until it gets to 350. You probably wanted it to rotate only 20 degrees, passing through 0. The
solution is to check the "Rotate in shortest direction" checkbox from the popup window. This will cause
the line to always pick the rotation direction that has a total rotation of less than 180 degrees.

New feature: ignore text. Requires you to only have one tag block in each line, at the beginning.


Comes with an extra automation "Remove tags" that utilizes functions that were written for the main
automation. You can comment out (two dashes) the line at the bottom that adds this automation if you don't
want it.


TODO:
Check that all lines text match
iclip support

]]

export script_name = "Frame-by-frame transform"
export script_description = "Smoothly transforms between the first and last selected lines."
export script_version = "1.1.0"
export script_namespace = "lyger.FbfTransform"

DependencyControl = require "l0.DependencyControl"
rec = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json",
    {
        "aegisub.util",
        {"lyger.LibLyger", version: "1.1.0", url: "http://github.com/TypesettingTools/lyger-Aegisub-Scripts"},
        {"l0.ASSFoundation.Common", version: "0.2.0", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"}
    }
}
util, LibLyger, Common = rec\requireModules!
have_SubInspector = rec\checkOptionalModules "SubInspector.Inspector"
logger, libLyger = rec\getLogger!, LibLyger!

-- tag list, grouped by dialog layout
tags_grouped = {
    {"c", "2c", "3c", "4c"},
    {"alpha", "1a", "2a", "3a", "4a"},
    {"fscx", "fscy", "fax", "fay"},
    {"frx", "fry", "frz"},
    {"bord", "shad", "fs", "fsp"},
    {"xbord", "ybord", "xshad", "yshad"},
    {"blur", "be"},
    {"pos", "org", "clip"}
}
tags_flat = table.join unpack tags_grouped

-- default settings for every preset
preset_defaults = { skiptext: false, flip_rot: false, accel: 1.0,
                    tags: {tag, false for tag in *tags_flat }
}

-- the default preset must always be available and cannot be deleted
config = rec\getConfigHandler {
    presets: {
        Default: {}
        "[Last Settings]": {description: "Repeats the last #{script_name} operation"}
    }
    startupPreset: "Default"
}
unless config\load!
    -- write example preset on first time load
    config.c.presets["All"] = tags: {tag, true for tag in *tags_flat}
    config\write!

create_dialog = (preset) ->
    config\load!
    preset_names = [preset for preset, _ in pairs config.c.presets]
    table.sort preset_names
    dlg = {
        -- Flip rotation
        { name: "flip_rot",      class: "checkbox",  x: 0, y: 9, width: 3, height: 1,
          label: "Rotate in shortest direction", value: preset.c.flip_rot              },
        { name: "skiptext",      class: "checkbox",  x: 3, y: 9, width: 2, height: 1,
          label: "Ignore text",                  value: preset.c.skiptext              },
        -- Acceleration
        {                        class: "label",     x: 0, y: 10, width: 2, height: 1,
          label: "Acceleration: ",                                                     },
        { name: "accel",         class:"floatedit",  x: 2, y: 10, width: 3, height: 1,
          value: preset.c.accel, hint: "1 means no acceleration, >1 starts slow and ends fast, <1 starts fast and ends slow" },
        {                        class: "label",     x: 0, y: 11, width: 2, height: 1,
          label: "Preset: "                                                            },
        { name: "preset_select", class: "dropdown",  x: 2, y: 11, width: 2, height: 1,
          items: preset_names, value: preset.section[#preset.section]                  },
        { name: "preset_modify", class: "dropdown",  x: 4, y: 11, width: 2, height: 1,
          items: {"Load", "Save", "Delete", "Rename"}, value: "Load" }
    }

    -- generate tag checkboxes
    for y, group in ipairs tags_grouped
        dlg[#dlg+1] = { name: tag, class: "checkbox", x: x-1, y: y, width: 1, height: 1,
                        label: "\\#{tag}", value: preset.c.tags[tag] } for x, tag in ipairs group

    btn, res = aegisub.dialog.display dlg, {"OK", "Cancel", "Mod Preset", "Create Preset"}
    return btn, res, preset

save_preset = (preset, res) ->
    preset\import res, nil, true
    if res.__class != DependencyControl.ConfigHandler
        preset.c.tags[k] = res[k] for k in *tags_flat
    preset\write!

create_preset = (settings, name) ->
    msg = if not name
        "Onii-chan, what name would you like your preset to listen to?"
    elseif name == ""
        "Onii-chan, did you forget to name the preset?"
    elseif config.c.presets[name]
        "Onii-chan, it's not good to name a preset the same thing as another one~"

    if msg
        btn, res = aegisub.dialog.display {
            { class: "label", x: 0, y: 0, width: 2, height: 1, label: msg               }
            { class: "label", x: 0, y: 1, width: 1, height: 1, label: "Preset Name: "   },
            { class: "edit",  x: 1, y: 1, width: 1, height: 1, name: "name", text: name }
        }
        return btn and create_preset settings, res.name

    preset = config\getSectionHandler {"presets", name}, preset_defaults
    save_preset preset, settings
    return name

prepare_line = (i, preset) ->
    line = libLyger.lines[i]

    -- Figure out the correct position and origin values
    posx, posy = libLyger\get_pos line
    orgx, orgy = libLyger\get_org line

    -- Look for clips
    clip = {line.text\match "\\clip%(([%d%.%-]*),([%d%.%-]*),([%d%.%-]*),([%d%.%-]*)%)"}

    -- Make sure each line starts with tags
    line.text = "{}#{line.text}" unless line.text\find "^{"
    -- Turn all \1c tags into \c tags, just for convenience
    line.text = line.text\gsub "\\1c", "\\c"

    --Separate line into a table of tags and text
    line_table = if preset.c.skiptext
        while not line.text\match "^{[^}]+}[^{]"
            line.text = line.text\gsub "}{", "", 1
        tag, text = line.text\match "^({[^}]+})(.+)$"
        {{:tag, :text}}
    else [{:tag, :text} for tag, text in line.text\gmatch "({[^}]*})([^{]*)"]

    return line, line_table, posx, posy, orgx, orgy, #clip > 0 and clip

--The main body of code that runs the frame transform
frame_transform = (sub, sel, res) ->
    -- save last settings
    preset = config\getSectionHandler {"presets", "[Last Settings]"}, preset_defaults
    save_preset preset, res

    libLyger\set_sub sub
    -- Set the first and last lines in the selection
    first_line, start_table, sposx, sposy, sorgx, sorgy, sclip = prepare_line sel[1], preset
    last_line, end_table, eposx, eposy, eorgx, eorgy, eclip = prepare_line sel[#sel], preset

    -- If either the first or last line do not contain a rectangular clip,
    -- you will not be clipping today
    preset.c.tags.clip = false unless sclip and eclip
    -- These are the tags to transform
    transform_tags = [tag for tag in *tags_flat when preset.c.tags[tag]]

    -- Make sure both lines have the same splits
    LibLyger.match_splits start_table, end_table

    -- Tables that store tables for each tag block, consisting of the state of all relevant tags
    -- that are in the transform_tags table
    start_state_table = LibLyger.make_state_table start_table, transform_tags
    end_state_table = LibLyger.make_state_table end_table, transform_tags

    -- Insert default values when not included for the state of each tag block,
    -- or inherit values from previous tag block
    start_style = libLyger\style_lookup first_line
    end_style =   libLyger\style_lookup last_line

    current_end_state, current_start_state = {}, {}

    for k, sval in ipairs start_state_table
        -- build current state tables
        for skey, sparam in pairs sval
            current_start_state[skey] = sparam

        for ekey, eparam in pairs end_state_table[k]
            current_end_state[ekey] = eparam

        -- check if end is missing any tags that start has
        for skey, sparam in pairs sval
            end_state_table[k][skey] or= current_end_state[skey] or end_style[skey]

        -- check if start is missing any tags that end has
        for ekey, eparam in pairs end_state_table[ k]
            start_state_table[k][ekey] or= current_start_state[ekey] or start_style[ekey]

    -- Insert proper state into each intervening line
    for i = 2, #sel-1
        aegisub.progress.set 100 * (i-1) / (#sel-1)
        this_line = libLyger.lines[sel[i]]

        -- Turn all \1c tags into \c tags, just for convenience
        this_line.text = this_line.text\gsub "\\1c","\\c"

        -- Remove all the relevant tags so they can be replaced with their proper interpolated values
        this_line.text = LibLyger.time_exclude this_line.text, transform_tags
        this_line.text = LibLyger.line_exclude this_line.text, transform_tags
        this_line.text = this_line.text\gsub "{}",""

        -- Make sure this line starts with tags
        this_line.text = "{}#{this_line.text}" unless this_line.text\find "^{"

        -- The interpolation factor for this particular line
        factor = (i-1)^preset.c.accel / (#sel-1)^preset.c.accel

        -- Handle pos transform
        if preset.c.tags.pos then
            x = LibLyger.float2str util.interpolate factor, sposx, eposx
            y = LibLyger.float2str util.interpolate factor, sposy, eposy
            this_line.text = this_line.text\gsub "^{", "{\\pos(#{x},#{y})"

        -- Handle org transform
        if preset.c.tags.org then
            x = LibLyger.float2str util.interpolate factor, sorgx, eorgx
            y = LibLyger.float2str util.interpolate factor, sorgy, eorgy
            this_line.text = this_line.text\gsub "^{", "{\\org(#{x},#{y})"

        -- Handle clip transform
        if preset.c.tags.clip then
            clip = [util.interpolate factor, ord, eclip[i] for i, ord in ipairs sclip]
            logger\dump{clip, sclip, eclip}
            this_line.text = this_line.text\gsub "^{", "{\\clip(%d,%d,%d,%d)"\format unpack clip

        -- Break the line into a table
        local this_table
        if preset.c.skiptext
            while not this_line.text\match "^{[^}]+}[^{]"
                this_line.text = this_line.text\gsub "}{", "", 1
            tag, text = line.text\match "^({[^}]+})(.+)$"
            this_table = {{:tag, :text}}
        else
            this_table = [{:tag, :text} for tag, text in this_line.text\gmatch "({[^}]*})([^{]*)"]
            -- Make sure it has the same splits
            j = 1
            while j <= #start_table
                stext, stag = start_table[j].text, start_table[j].tag
                ttext, ttag = this_table[j].text, this_table[j].tag

                -- ttext might contain miscellaneous tags that are not being checked for,
                -- so remove them temporarily
                ttext_temp = ttext\gsub "{[^{}]*}", ""

                -- If this table item has longer text, break it in two based on
                -- the text of the start table
                if #ttext_temp > #stext
                    newtext = ttext_temp\match "#{LibLyger.esc stext}(.*)"
                    for i = #this_table, j+1,-1
                        this_table[i+1] = this_table[i]

                    this_table[j] = tag: ttag, text: ttext\gsub "#{LibLyger.esc newtext}$",""
                    this_table[j+1] = tag: "{}", text: newtext

                -- If the start table has longer text, then perhaps ttext was split
                -- at a tag that's not being transformed
                if #ttext < #stext
                    -- It should be impossible for this to happen at the end, but check anyway
                    assert this_table[j+1], "You fucked up big time somewhere. Sorry."

                    this_table[j].text = table.concat {ttext, this_table[j+1].tag, this_table[j+1].text}
                    if this_table[j+2]
                        this_table[i] = this_table[i+1] for i = j+1, #this_table-1

                    this_table[#this_table] = nil
                    j -= 1

                j += 1

        --Interpolate all the relevant parameters and insert
        this_line.text = LibLyger.interpolate this_table, start_state_table, end_state_table,
                                              factor, preset
        sub[sel[i]] = this_line


validate_fbf = (sub, sel) -> #sel >= 3

load_tags_remove = (sub, sel) ->
    pressed, res = aegisub.dialog.display {
        { class: "label", label: "Enter the tags you would like to remove: ",
          x: 0, y: 0, width: 1,height: 1 },
        { class: "textbox", name: "tag_list", text: "",
          x: 0, y: 1,width: 1, height: 1 },
        { class: "checkbox", label: "Remove all EXCEPT", name: "do_except", value: false,
          x: 0,y: 2, width: 1, height: 1 }
    }, {"Remove","Cancel"}, {ok: "Remove", cancel: "Cancel"}

    return if pressed == "Cancel"

    tag_list = [tag for tag in res.tag_list\gmatch "\\?(%w+)[%s\\n,;]*"]

    --Remove or remove except the tags in the table
    for li in *sel
        line = sub[li]
        f = res.do_except and LibLyger.line_exclude_except or LibLyger.line_exclude
        line.text = f(line.text, tag_list)\gsub "{}", ""
        sub[li] = line

fbf_gui = (sub, sel, _, preset_name = config.c.startupPreset) ->
    preset = config\getSectionHandler {"presets", preset_name}, preset_defaults
    btn, res = create_dialog preset

    switch btn
        when "OK" do frame_transform sub, sel, res
        when "Create Preset" do fbf_gui sub, sel, nil, create_preset res
        when "Mod Preset"
            if preset_name != res.preset_select
                preset = config\getSectionHandler {"presets", res.preset_select}, preset_defaults
                preset_name = res.preset_select

            switch res.preset_modify
                when "Delete"
                    preset\delete!
                    preset_name = nil
                when "Save" do save_preset preset, res
                when "Rename"
                    preset_name = create_preset preset.userConfig, preset_name
                    preset\delete!
            fbf_gui sub, sel, nil, preset_name

-- register macros
rec\registerMacros {
    {script_name, nil, fbf_gui, validate_fbf},
    {"Remove tags", "Remove or remove all except the input tags.", load_tags_remove}
}
for name, preset in pairs config.c.presets
    f = (sub, sel) -> frame_transform sub, sel, config\getSectionHandler {"presets", name}
    rec\registerMacro "Presets/#{name}", preset.description, f, validate_fbf, nil, true