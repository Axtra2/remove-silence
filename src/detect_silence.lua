---@type fun(data: string): [{from: number, to: number}]?
local function parse_detect_silence_output_string(data)
    ---@type [number]
    local starts = {}
    for s in data:gmatch("silencedetect.-silence_start:%s+(%d+%.?%d*)") do
        starts[#starts+1] = tonumber(s)
    end

    ---@type [number]
    local ends = {}
    for s in data:gmatch("silencedetect.-silence_end:%s+(%d+%.?%d*)") do
        ends[#ends+1] = tonumber(s)
    end

    if #starts ~= #ends then
        print("error: ill-formed silence periods (#starts != #ends)")
        return nil
    end

    for i = 1, #starts do
        if starts[i] > ends[i] then
            print("error: ill-formed silence periods (start > end)")
            return nil
        end
    end

    ---@type [{from: number, to: number}]
    local res = {}

    for i = 1, #starts do
        res[#res+1] = {
            from = starts[i],
            to = ends[i]
        }
    end

    return res
end

---@type fun(filename: string): [{from: number, to: number}]?
local function parse_detect_silence_output_file(filename)
    local detect_silence_output_file = io.open(filename)
    if detect_silence_output_file == nil then
        print("error: could not open \"" .. filename .. "\"")
        return nil
    end

    ---@type string
    local detect_silence_output_string = detect_silence_output_file:read("a")

    detect_silence_output_file:close()

    return parse_detect_silence_output_string(detect_silence_output_string)
end

---@type fun(input_filename: string,output_filename: string, noise_threshold_in_db: number, min_silence_duration_in_seconds: number): [{from: number, to: number}]?
local function detect_silence_using_ffmpeg(
    input_filename,
    output_filename,
    noise_threshold_in_db,
    min_silence_duration_in_seconds
)
    ---@type string
    local cmd_format = "ffmpeg -i \"%s\" -af silencedetect=n=%fdB:d=%f -f null - 2> \"%s\""
    ---@type string
    local cmd = cmd_format:format(
        input_filename,
        noise_threshold_in_db,
        min_silence_duration_in_seconds,
        output_filename
    )
    if not os.execute(cmd) then
        print("error: could not execute ffmpeg's silence detect")
        return nil
    end

    return parse_detect_silence_output_file(output_filename)
end

---@type fun(filename: string): seconds: number?
local function get_video_duration(filename)
    local cmd_format =
        "ffprobe -v error -show_entries format=duration " ..
        "-of default=noprint_wrappers=1:nokey=1 -i \"%s\""
    local output = io.popen(cmd_format:format(filename))
    if output == nil then
        print("error: could not get the duration of \"" .. filename .. "\"")
        return nil
    end
    local res = tonumber(output:read("a"))
    if res == nil then
        print("error: could not get the duration of \"" .. filename .. "\"")
        return nil
    end
    return res
end

---@type fun(splits: [{from: number, to: number?}], video_duration: number?): new_splits: [{from: number, to: number?}]
local function invert_time_periods(splits, video_duration)
    if #splits == 0 then
        return {}
    end

    ---@type [{from: number, to: number?}]
    local new_splits = {}

    if math.abs(splits[1].from) > 0.01 then
        new_splits[#new_splits+1] = {
            from = 0.0,
            to = splits[1].from
        }
    end

    for i = 2, #splits do
        new_splits[#new_splits+1] = {
            from = splits[i - 1].to,
            to = splits[i].from
        }
    end

    if video_duration ~= nil then
        if math.abs(splits[#splits].to - video_duration) > 0.01 then
            new_splits[#new_splits+1] = {
                from = splits[#splits].to,
                to = video_duration
            }
        end
    else
        new_splits[#new_splits+1] = {
            from = splits[#splits].to,
            to = nil
        }
    end

    return new_splits
end

---@type fun(splits: [{from: number, to: number?}], padding_in_seconds: number, video_duration: number?): new_splits: [{from: number, to: number?}]
local function add_padding(splits, padding_in_seconds, video_duration)
    ---@type [{from: number, to: number?}]
    local new_splits = {}
    for _, split in ipairs(splits) do
        new_splits[#new_splits+1] = {
            from = split.from - padding_in_seconds,
            to = split.to ~= nil and split.to + padding_in_seconds or nil
        }
    end
    if new_splits[1].from < 0.0 then
        new_splits[1].from = 0.0
    end
    if video_duration ~= nil then
        if new_splits[#new_splits].to > video_duration then
            new_splits[#new_splits].to = video_duration
        end
    end
    return new_splits
end

return {
    parse_detect_silence_output_file=parse_detect_silence_output_file,
    detect_silence_using_ffmpeg=detect_silence_using_ffmpeg,
    invert_time_periods=invert_time_periods,
    get_video_duration=get_video_duration,
    add_padding=add_padding
}
