local fs_utils = require("src.win_fs_utils")
local detect_silence = require("src.detect_silence")


---@type number
NOISE_THRESHOLD_IN_DB = -50

---@type number
MIN_SILENCE_DURATION_IN_SECONDS = 0.5

---@type number
PADDING_IN_SECONDS = 0.1
if PADDING_IN_SECONDS * 2 > MIN_SILENCE_DURATION_IN_SECONDS then
    print("warning: padding * 2 > silence; video parts may overlap")
end


local TMP_DIR = "tmp"
if not fs_utils.exists(TMP_DIR) then
    if not fs_utils.mkdir(TMP_DIR) then
        print("error: could not create temporary folder")
        os.exit(1)
    end
end


local USAGE = ([[
USAGE:
%s input_filename [output_filename] [--skip_analysis detect_silence_file] [--ffmpeg_path PATH_TO_FFMPEG]
]]):format(arg[0])


local input_filename = nil
local output_filename = nil
local skip_analysis = false
local ffmpeg_path = ""

---@type string
local detect_silence_filename

---@type { [string]: fun(arg_index: integer): next_arg_index: integer }
local FLAGS = {
    ["--skip_analysis"] = function (i)
        if skip_analysis then
            print("error: \"--skip_analysis\" flag encountered more that once")
            print(USAGE)
            os.exit(1)
        end
        if i + 1 > #arg then
            print("error: expected filename after \"--skip_analysis\" flag")
            print(USAGE)
            os.exit(1)
        end
        skip_analysis = true
        detect_silence_filename = arg[i + 1]
        return i + 2
    end,
    ["--ffmpeg_path"] = function (i)
        if i + 1 > #arg then
            print("error: expected path to ffmpeg after \"--ffmpeg-path\" flag")
            print(USAGE)
            os.exit(1)
        end
        ffmpeg_path = arg[i + 1]
        return i + 2
    end
}

if #arg < 1 or #arg > 4 then
    print("error: wrong number of arguments")
    print(USAGE)
    os.exit(1)
end

local i = 1
while i <= #arg do
    if arg[i]:sub(1, 1) == "-" then
        local flag_handler = FLAGS[arg[i]]
        if flag_handler == nil then
            print("error: unrecognized option \"" .. arg[i] .. "\"")
            print(USAGE)
            os.exit(1)
        end
        i = flag_handler(i)
        goto continue
    end
    if input_filename == nil then
        input_filename = arg[i]
    elseif output_filename == nil then
        output_filename = arg[i]
    else
        print()
        print("error: too many files")
        print(USAGE)
        os.exit(1)
    end
    i = i + 1
    ::continue::
end


if input_filename == nil then
    print("error: no input file")
    os.exit(1)
end


if output_filename == nil then
    local suffix = "-nosilence"
    print(
        "warning: no output file specified; " ..
        "the output file will have suffix \"" .. suffix .. "\""
    )

    local name, ext = fs_utils.split_filename(input_filename)
    output_filename = name .. suffix .. "." .. ext
end



if not fs_utils.exists(input_filename) then
    print("error: could not locate file \"" .. input_filename .. "\"")
    os.exit(1)
end

if fs_utils.exists(output_filename) then
    print("error: output file already exists")
    os.exit(1)
end


local silence_starts_ends_table

if skip_analysis then
    print("parsing \"" .. detect_silence_filename .. "\"...")
    silence_starts_ends_table = detect_silence.parse_detect_silence_output_file(detect_silence_filename)
else
    print("analysing \"" .. input_filename .. "\"...")
    silence_starts_ends_table = detect_silence.detect_silence_using_ffmpeg(
        ffmpeg_path,
        input_filename,
        TMP_DIR .. os.tmpname():match("\\([^\\]+)$"),
        NOISE_THRESHOLD_IN_DB,
        MIN_SILENCE_DURATION_IN_SECONDS
    )
end

if silence_starts_ends_table == nil then
    print("error: could not detect silence")
    os.exit(1)
end

print("detected " .. #silence_starts_ends_table .. " silent periods")

local video_duration = detect_silence.get_video_duration(ffmpeg_path, input_filename)
if video_duration == nil then
    print(
        "warning: failed to get video duration; " ..
        "the last non-silent part of the video may be cut"
    )
end


local splits = detect_silence.invert_time_periods(
    silence_starts_ends_table,
    video_duration
)

splits = detect_silence.add_padding(splits, PADDING_IN_SECONDS, video_duration)


print("generating cutting script...")


local bat = io.open(TMP_DIR .. "/cut.bat", "w+")
if not bat then
    print("error: could not open \"" .. TMP_DIR .. "/cut.bat\"")
    os.exit(1)
end

local list = io.open(TMP_DIR .. "/list.txt", "w+")
if not list then
    print("error: could not open \"" .. TMP_DIR .. "/list.txt\"")
    os.exit(1)
end


---@type fun(i: integer): string
local function gen_part_name(i)
    local no_ext_filename = fs_utils.split_filename(input_filename)
    local n_digits = math.ceil(math.log(#splits, 10))
    local format_string = "%s-part-%0" .. n_digits .. "d.mp4"
    return format_string:format(no_ext_filename, i)
end


---@type string
local format_string = "%sffmpeg -n -v fatal -accurate_seek %s %s -i \"%s\" \"%s\""

---@type string
local from_format = "-ss %.2f"

---@type string
local to_format = "-to %.2f"

---@type string
local list_format = "file '%s'"


bat:write("@echo off\n\n")
for index, split in ipairs(splits) do
    -- if index > 10 then
    --     break
    -- end
    local part_filename = gen_part_name(index - 1)
    local cmd = format_string:format(
        ffmpeg_path,
        from_format:format(split.from),
        split.to == nil and "" or to_format:format(split.to),
        input_filename,
        part_filename
    )
    local d = math.ceil(math.log(#splits, 10))
    cmd = string.format("echo processing part %0" .. d .. "d/%d\n", index, #splits) .. cmd
    bat:write(cmd .. "\n\n")
    list:write(list_format:format(part_filename) .. "\n")
end

list:close()
bat:close()


print("cutting...")
os.execute(TMP_DIR .. "\\cut.bat")

print("concatenating...")

local concat_format = ffmpeg_path .. "ffmpeg -v error -f concat -safe 0 -i \"%s\" -c copy \"%s\""
os.execute(concat_format:format(TMP_DIR .. "/list.txt", output_filename))


print("done")

os.exit(0)
