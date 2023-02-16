
--------------------------------------------
---- source code from l3build.lua
--------------------------------------------

local lfs = require("lfs")

local assert           = assert
local ipairs           = ipairs
local insert           = table.insert
local lookup           = kpse.lookup
local match            = string.match
local gsub             = string.gsub

kpse.set_program_name("kpsewhich")
build_kpse_path = match(lookup("l3build.lua"),"(.*[/])")
local function build_require(s)
  require(lookup("l3build-"..s..".lua", { path = build_kpse_path } ) )
end

-----------------------------------------

build_require("file-functions")

release_date = "2021-04-26" -- for old build.lua file
dofile("build.lua")

build_require("variables")

imgext = imgext or ".png"

--[[
  testdir - all updated images
  dirrdir - selective images, md5, and diff images (*.diff-n.png) updated or 
            generated for failed or no md5 tests
]] 
local diffdir = testdir .. "/updated"
if direxists(diffdir) then
  cleandir(diffdir)
else
  mkdir(diffdir)
end

local md5 = require("md5")

local function md5sum(str)
  if str then return md5.sumhexa(str) end
end

local function filesum(name)
  local f = assert(io.open(name, "rb"))
  local s = f:read("*all")
  f:close()
  return md5sum(s)
end

local function readfile(name)
  local f = assert(io.open(name, "rb"))
  local s = f:read("*all")
  f:close()
  return s
end

local function writefile(name, sum)
  local f = assert(io.open(name, "w"))
  f:write(sum)
  f:close()
end

local function getimgopt(imgext)
  local imgopt = ""
  if imgext == ".png" then
    imgopt = " -png "
  elseif imgext == ".ppm" then
    imgopt = " "
  elseif imgext == ".pgm" then
    imgopt = " -gray "
  elseif imgext == ".pbm" then
    imgopt = " -mono "
  else
    error("unsupported image extension" .. imgext)
  end
  return imgopt
end

local function pdftoimg(path, pdf)
  cmd = "pdftoppm " .. getimgopt(imgext) .. pdf .. " " .. jobname(pdf)
  run(path, cmd)
end

-- backup - diffdir
-- save   - testfiledir
local function backup_new_md5(md5name, newmd5)
  print("  backup new md5 " .. md5name)
  writefile(diffdir .. "/" .. md5name, newmd5)
end

local function backup_img(imgname)
  print("  backup image " .. imgname)
  cp(imgname, testdir, diffdir)
end

-- save updated files to testfiledir
local function save_img_and_md5(imgname, md5name)
  print("  save image and md5 files for " .. imgname)
  cp(imgname, diffdir, testfiledir)
  cp(md5name, diffdir, testfiledir)
end

local function ppmcheck(job)
  local errorlevel
  local imgname = job .. imgext
  local md5name = job .. ".md5"
  local md5file = testfiledir .. "/" .. md5name
  local newmd5 = filesum(testdir .. "/" .. imgname)

  if fileexists(md5file) then
    local oldmd5 = readfile(md5file)
    if newmd5 == oldmd5 then
      errorlevel = 0
      print("md5 check passed for " .. imgname)
    else
      errorlevel = 1
      print("md5 check failed for " .. imgname)
      backup_new_md5(md5name, newmd5)
      backup_img(imgname)

      -- "convert" from imagemagick
      local imgdiffexe = os.getenv("imgdiffexe")
      if imgdiffexe then
        local oldimg = abspath(testfiledir) .. "/" .. imgname
        local newimg = abspath(testdir) .. "/" .. imgname
        local diffname = job .. ".diff.png"
        local cmd = imgdiffexe .. " " .. oldimg .. " " .. newimg
                    .. " -compose src " .. diffname
        print("  create image diff files " .. job .. ".diff-n.png")
        run(diffdir, cmd)
      elseif arg[1] == "save" then
        save_img_and_md5(imgname, md5name)
      end
    end
  else
    errorlevel = 0
    backup_new_md5(md5name, newmd5)
    backup_img(imgname) -- in case image is updated
    save_img_and_md5(imgname, md5name)
  end
  return errorlevel
end

local function main()
  local errorlevel = 0
  local files = ordered_filelist(testdir, "*" .. pdfext)
  for _, v in ipairs(files) do
    pdftoimg(testdir, v)
    pattern = "^" .. jobname(v):gsub("%-", "%%-") .. "%-%d+%" .. imgext .. "$"
    glob = jobname(v) .. "-*" .. imgext
    local imgfiles = ordered_filelist(testdir, glob)
    if #imgfiles == 1 then
      local imgname = jobname(v) .. imgext
      if fileexists(testdir .. "/" .. imgname) then
        rm(testdir, imgname)
      end
      ren(testdir, imgfiles[1], imgname)
      local e = ppmcheck(jobname(v)) or 0
      errorlevel = errorlevel + e
    else
      for _, i in ipairs(imgfiles) do
        local e = ppmcheck(jobname(i)) or 0
        errorlevel = errorlevel + e
      end
    end
  end
  return errorlevel
end

local errorlevel = main()
if os.type == "windows" then os.exit(errorlevel) end
