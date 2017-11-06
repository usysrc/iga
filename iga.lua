--[[
	IMAGE GENERATION ALGORITHM
	
	Based on & heavily inspired by the WaveFunctionCollapse (WFC) algorithm by mxgmn: https://github.com/mxgmn/WaveFunctionCollapse
	Executable & the .mfa source made using Multimedia Fusion 2 by Clickteam
	
	The MIT License
	Copyright 2017 Arvi Teikari
	Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
	The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	
	Note that commercial use of the .mfa source file may be limited by Clickteam's licenses. Please refer to those if needed.
]]--

--[[
	additional code and refactoring by headchant 2017
]]--

-- NOTE: Many of the variables refer to 'cells', even in cases where two such variables are actually handling a completely different thing. I've tried to clarify things in the comments by differentiating between 'pixels' (i.e. single pixels in the output data or the input data) and 'chunks' (i.e. N*N clusters of pixels, usually in the input data)

-- This function resets everything and sets up the necessary lua arrays for the generation
local iga = {}

local output_width, output_height, input_width, input_height
local colours, wave, entropy, N, colourids
local colourids, input, inputids, total_colours

-- Checks for if a pixel is out of boundaries
local function inbounds_output(x,y)
	return (x >= 0) and (y >= 0) and (x < output_width) and (y < output_height)
end

local function inbounds_input(x,y)
	return (x >= 0) and (y >= 0) and (x < input_width) and (y < input_height)
end

function iga:getColours()
	return colours
end

function iga:geninit(img, ow,oh,iw,ih,N_)
	-- Dimensions of the output/input are given by MMF2
	output_width = ow
	output_height = oh
	input_width = iw
	input_height = ih
	
	-- N is the size of the 'chunk' we'll use for detecting similarities between the input and output. 3 is the default as in the WFC algorithm
	-- NOTE: The calculation math.floor(N/2) will be used a lot in the code. This essentially gives us the 'radius' of N, making it easy to calculate an N*N region around a given point
	N = N_
	
	-- Here are the various 2d arrays used to calculate the generation. Short explanations:
	-- Wave: Marks output image's pixels as either handled (1) or not handled (0)
	-- Entropy: Saves the 'entropy' of every output pixel, i.e. how 'easy' that pixel is to compute and thus how much priority it has (lower = better). The 'Wave' and 'Entropy' names come directly from the WFC algorithm
	-- Colours: To handle as much as possible on lua's side, the RGB value of every output pixel is stored here. This way only the visual colours need to be handled in MMF
	-- Colourids: Every colour in the input image will be given an ID which'll be stored here
	-- Input: Similarly to the colours array, the RGB values of every input pixel is stored here to make things faster
	-- Inputids: Some more data for input image pixels; explained more below
	wave = {}
	entropy = {}
	colours = {}
	colourids = {}
	
	-- RGB value zero is essentially treated as 'empty' space in the algorithm, so the first colourid is manually assigned for it
	colourids[0] = 0
	
	input = {}
	inputids = {}

	total_colours = 0

	-- Note that the output image is always empty when this function is run, hence resetting its pixels to defaults (and ensuring no pixel has a nil value)
	for i=0,output_width-1 do
		for j=0,output_height-1 do
			local id = i + j * output_width
			wave[id] = 0
			-- The value given here is completely arbitrary; the basic idea is that the default entropy of a pixel is high enough that it never gets priority unless there's nothing else available
			entropy[id] = math.random(3600,4500)
			colours[id] = 0
		end
	end
	local data = img:getData()
	for i=0,input_width-1 do
		for j=0,input_height-1 do
			local id = i + j * input_width
			-- MF_getrgb fetches the colour of a given pixel of the input image from MMF's side
			local r,g,b = data:getPixel(i,j)
			local colour = string.format("%03d%03d%03d",r,g,b)
			colour = tonumber(colour)
			input[id] = colour
			
			-- If there doesn't exist an entry for the fetched colour, add 1 to total_colours and give said colour a unique ID
			if (colourids[colour] == nil) then
				total_colours = total_colours + 1
				colourids[colour] = total_colours
			end
		end
	end
	
	local dim = math.floor(N/2)
	
	-- Next comes the somewhat complicated bit of the setup; for every N*N chunk in the input image, we calculate a unique ID based on the colours in the pixels inside that chunk
	for i=dim,input_width-1-dim do
		for j=dim,input_height-1-dim do
			local id = i + j * input_width
			inputids[id] = {}
			-- two things are stored in inputids for every pixel: the colours of the pixels surrounding it (in an N*N region) and the unique ID of said pixel
			local currid = inputids[id]
			
			-- Getinputcell(x, y) creates a table stored with the colour of every pixel in the N*N chunk around x,y
			currid.colours = iga:getinputcell(i,j)
			
			currid.colourid = 0

			for a=0,N-1 do
				for b=0,N-1 do
					-- cx,cy denote the actual position of the pixel we are looking at
					local cx = i - math.floor(N/2) + a
					local cy = j - math.floor(N/2) + b
					local cid = cx + cy * input_width
					-- Chunkid is the ID of the current pixel within the N*N region (with top-left being 0, top-center 1, top-right 2 etc)
					local chunkid = a + b * N
					local colour = input[cid]
					colour = colourids[colour]
					-- The unique ID is calculated in a way that ensures that even if two N*N chunks had the same combination of coloured pixels, they'd get the same ID only if they were completely identical
					currid.colourid = currid.colourid + colour * (total_colours ^ chunkid)
				end
			end
		end
	end
end

function iga:genstep()
	local cell = 0
	local cellx,celly = 0,0
	local found = false
	local empty = 0
	local attempts = 0
	
	-- We go through the pixels in the output image to find the one with the lowest entropy
	while (found == false) do
		local maxe = 10000
		local test = false
		for id,done in pairs(wave) do
			local e = entropy[id]
			
			if (e < maxe) and (done ~= 1) then
				maxe = e
				cell = id
				cellx = math.floor(cell % output_width)
				celly = math.floor(cell / output_width)
				test = true
			end
		end
		
		-- If all pixels are marked as handled, the function returns true (so that the generation knows to halt)
		if (test == false) then
			return true
		end
		
		-- Checks if the chosen pixel & the pixels surrounding it are not handled yet; probably an unnecessary check
		empty = iga:isempty(cellx,celly)
		
		if (empty == 0) then
			wave[cell] = 1
			attempts = attempts + 1
		else
			found = true
			break
		end
		
		if (attempts > 20) then
			found = true
			break
		end
	end
	
	if (empty == 1) then
		local validcells = {}

		validcells = iga:fit(cellx,celly)
		iga:handlecells(validcells,cellx,celly)
		
		wave[cell] = 1
	end
	
	return false
end

-- Pretty self-explanatory; draw() draws an N*N chunk of the input image onto the output image
function iga:draw(targetcell,x,y)
	local ix = targetcell.c % input_width
	local iy = math.floor(targetcell.c / input_width)
	
	local id = x + y * output_width
	wave[id] = 1
	
	-- It's important to update the colour array since we're using that instead of the actual image 
	for i=0,N-1 do
		for j=0,N-1 do
			local input_x = ix - math.floor(N / 2) + i
			local input_y = iy - math.floor(N / 2) + j
			local output_x = x - math.floor(N / 2) + i
			local output_y = y - math.floor(N / 2) + j
			
			if inbounds_output(output_x,output_y) and inbounds_input(input_x,input_y) then
				local output_id = output_x + output_y * output_width 
				local input_id = input_x + input_y * input_width
				colours[output_id] = input[input_id]
			end
		end
	end
	
	-- The drawing must be done on MMF's side, but this should be pretty self-explanatory
	if inbounds_output(x,y) then
		--MF_draw(x,y,ix,iy)
	end
end

-- Once a pixel is handled on a step, new entropies are calculated for the pixels immediately surrounding it (because the amount of valid input N*N chunks for them has decreased)
function iga:countentropy(x,y)
	for i=0,N-1 do
		for j=0,N-1 do
			local output_x = x - math.floor(N / 2) + i
			local output_y = y - math.floor(N / 2) + j
			local id = output_x + output_y * output_width
			
			if inbounds_output(output_x,output_y) then
				if (wave[id] == 0) then
					local validcells = iga:fit(output_x,output_y)
					
					-- If there's only one valid N*N chunk in the input image, immediately draw it and calculate the entropy again. Maybe makes things faster??
					-- The new entropy for a pixel is the amount of valid non-duplicate N*N chunks in the input image multiplied by 20 (probably an arbitrary choice)
					if (#validcells > 0) then
						if (#validcells == 1) then
							local targetcell = validcells[1]
							iga:draw(targetcell,output_x,output_y)
							--iga:countentropy(output_x,output_y)
							wave[id] = 1
						elseif (#validcells > 1) then
							local newentropy = 0
							for cid,validcell in ipairs(validcells) do
								if (validcell.d == 0) then
									newentropy = newentropy + 20
								elseif (validcell.d == 1) then
									-- d == 1 indicates that the cell is a duplicate and thus it doesn't increase entropy
									newentropy = newentropy + 0
								end
							end
							
							iga:update(output_x,output_y,newentropy)
							
							-- To make the algorithm smarter, once the entropy of a pixel is updated, we'll calculate new entropies for the pixels surrounding that pixel, too!
							for i=0,N-1 do
								for j=0,N-1 do
									local offset_x = output_x - math.floor(N / 2) + i
									local offset_y = output_y - math.floor(N / 2) + j
									
									if inbounds_output(offset_x,offset_y) then
										local offset_id = offset_x + offset_y * output_width
										
										if (entropy[offset_id] > 1000) and (wave[offset_id] == 0) then
											local valid = iga:fit(output_x,output_y)

											if (#valid > 0) then
												newentropy = 0
												for cid,validcell in ipairs(valid) do
													if (validcell.d == 0) then
														newentropy = newentropy + 20
													elseif (validcell.d == 1) then
														newentropy = newentropy + 0
													end
												end
												
												iga:update(offset_x,offset_y,newentropy)
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
end
-- A nice end staircase

-- handlecells() goes through all the N*N chunks that are valid for the output image pixel being handled, and draws them on the output image
	-- If there's one valid chunk, draw that and calculate entropies for the pixels surrounding x,y
	-- If there are multiple valid chunks, pick one at random, draw that (and calculate entropes)
function iga:handlecells(validcells,x,y)
	if (#validcells > 0) then
		if (#validcells == 1) then
			local targetcell = validcells[1]
			iga:draw(targetcell,x,y)
			iga:countentropy(x,y)
		elseif (#validcells > 1) then
			local rand = math.random(#validcells)
			local targetcell = validcells[rand]
			iga:draw(targetcell,x,y)
			iga:countentropy(x,y)
		end
	elseif (#validcells == 0) then
		-- Calculate new entropies even if no valid chunks were found
		iga:countentropy(x,y)
	end
end

-- Fit() is given an output image pixel, and it checks an N*N area around it and then finds all N*N chunks in the input image that would fit into that position (note that RGB value 0 is 'empty', i.e. disregarded)
function iga:fit(x,y)
	-- Celldata is a table with the colours of every pixel in an N*N chunk around x,y in the output image
	local celldata = {}
	celldata = iga:getcelldata(x,y)
	
	local validcells = {}

	-- To find all the valid chunks, we'll have to loop through the whole of the input image (barring the very edges)
	local dim = math.floor(N / 2)
	for i=dim,input_width-1-dim do
		for j=dim,input_height-1-dim do
			local cid = i + j * input_width
			local inputid = inputids[cid]
			
			-- Inputcell is the input image equivalent of celldata
			local inputcell = inputid.colours
			
			local success = true
			
			-- Colourid is the unique ID of the input image chunk being looked at
			local colourid = inputid.colourid
			
			-- Here we compare the corresponding pixel colours in the output chunk (a) and the input chunk (b)
			for id,b in pairs(inputcell) do
				local a = celldata[id]
				
				if (a ~= b) and (a > 0) and (b > 0) then
					success = false
				end
			end
			
			if success then
				local id = i + j * input_width

				-- We store the x,y coordinates of the input chunk (id), the unique ID of said chunk (colourid) and whether said chunk is a duplicate of another chunk (handled later)
				table.insert(validcells, {c = id, v = colourid, d = 0,})
			end
		end
	end
	
	local removethese = {}
	local existingids = {}
	
	-- Once the table with all the valid chunks has been formed, we go through it once more for an extra check and to mark all duplicates as such
	for id,cell in ipairs(validcells) do
		local i = cell.c % input_width
		local j = math.floor(cell.c / input_width)
		
		-- Extracheck() essentially checks if 4 extra pixels outside of the usual N*N region match in the input & output images
		-- This makes the result more predictable, but might be useless in situations where a more chaotic pattern is preferred
		local extracheck = iga:check(x,y,i,j)
		
		if (extracheck == 0) then
			table.insert(removethese, id)
		else
			-- Chunks that pass the extracheck() but which have already been encountered get marked as duplicates
			local cid = cell.v
			if (existingids[cid] == nil) then
				existingids[cid] = 1
			else
				cell.d = 1
			end
		end
	end
	
	-- Chunks that didn't pass the extracheck() get removed from validcells
	local count = 0
	for id,cell in ipairs(removethese) do
		local fullid = cell - count
		table.remove(validcells, fullid)
		count = count + 1
	end
	
	return validcells
end

-- Update the entropy of output pixel x,y
function iga:update(x,y,entropy_)
	local id = x + y * output_width
	
	entropy[id] = entropy_
end

-- Creates a table with the RGB values of every input image pixel in an N*N area around x,y (including the one at x,y)
function iga:getinputcell(x,y)
	local result = {}
	
	for i=0,N-1 do
		for j=0,N-1 do
			local input_x = x - math.floor(N / 2) + i
			local input_y = y - math.floor(N / 2) + j
			local id = input_x + input_y * input_width
			
			if inbounds_input(input_x,input_y) then
				table.insert(result, input[id])
			else
				table.insert(result, 0)
			end
		end
	end
	
	return result
end

-- Gets x,y coordinates from both the input image and the output image, and checks if 4 pixels beyond the usual N*N chunk range match between the two
-- The pixels being checked are: x+(N/2)+1,y; x-(N/2)-1,y; x,y+(N/2)+1; x,y-(N/2)-1
function iga:check(output_x,output_y,input_x,input_y)
	local result = 1
	local dim = math.floor(N/2)+1
	
	for i=0-dim,dim do
		for j=0-dim,dim do
			if (i == 0-dim) or (j == 0-dim) or (i == dim) or (j == dim) then
			-- The if clause below checks for 8 more pixels; it's stricter and thus could work better for certain inputs, but it seemed generally worse
			-- if ((i >= -1) and (i <= 1)) or ((j >= -1) and (j <= 1)) then
				if (i == 0) or (j == 0) then
					local ox = i
					local oy = j
					
					local output_colour = 0
					local input_colour = 0
					
					local offset_x = output_x + ox
					local offset_y = output_y + oy
					
					if inbounds_output(offset_x,offset_y) then
						local id = offset_x + offset_y * output_width
						output_colour = colours[id]
					end
					
					offset_x = input_x + ox
					offset_y = input_y + oy
					
					if inbounds_input(offset_x,offset_y) then
						local id = offset_x + offset_y * input_width
						input_colour = input[id]
					end
					
					if (output_colour > 0) and (input_colour > 0) and (output_colour ~= input_colour) then
						result = 0
					end
				end
			end
		end
	end
	
	return result
end

-- Creates a table with the RGB values of every output image pixel in an N*N area around x,y (including the one at x,y)
function iga:getcelldata(x,y)
	local result = {}
	for i=0,N-1 do
		for j=0,N-1 do
			local output_x = x - math.floor(N / 2) + i
			local output_y = y - math.floor(N / 2) + j
			local id = output_x + output_y * output_width
			
			if inbounds_output(output_x,output_y) then
				table.insert(result, colours[id])
			else
				table.insert(result, 0)
			end
		end
	end
	
	return result
end

-- Generates the whole output image in one go
function iga:generate()
	local done = false
	
	while (done == false) do
		-- Keeps running genstep() until there are no output pixels not handled; resets all the arrays when done (presumably to free memory? Probably unnecessary)
		done = genstep()
	
		if done then
			wave = nil
			entropy = nil
			input = nil
			inputids = nil
			colourids = nil
			colours = nil
			break
		end
	end
end

-- Checks if the pixels in an N*N area around x,y are 'empty' (i.e. if their RGB value is 0)
function iga:isempty(x,y)
	local result = 0
	for i=0,N-1 do
		for j=0,N-1 do
			local output_x = x - math.floor(N / 2) + i
			local output_y = y - math.floor(N / 2) + j
			local id = output_x + output_y * output_width
			local c = 0
			
			if inbounds_output(output_x,output_y) then
				c = colours[id]
			else
				-- pixels out of the boundaries of the output image are considered filled
				c = 1
			end
			
			if (c == 0) then
				result = 1
			end
		end
	end
	
	return result
end

-- Runs the generation for X steps; handy for visualization purposes
function iga:slowgen(steps_)
	local done = false
	local steps = 1
	
	if (steps_ ~= nil) then
		steps = steps_
	end
	
	for i=1,steps do
		done = genstep()
	end
	
	if done then
		return 1
	else
		return 0
	end
end

return iga