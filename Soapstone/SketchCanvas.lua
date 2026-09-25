local _, ns = ...

-- Draws a sketch grid on screen. WoW can't paint pixels into a texture, so
-- each row's runs of ink become solid rectangles, taken from a pool. Only rows
-- that changed are redrawn. An editable canvas also turns mouse drags into
-- strokes (left = selected tool, right = eraser) with per-stroke undo.

local Sketch = ns.Sketch

local SketchCanvas = {}
ns.SketchCanvas = SketchCanvas

SketchCanvas.PAPER = { 0.96, 0.95, 0.91 }
SketchCanvas.INK = { 0.07, 0.07, 0.07 }

local UNDO_LIMIT = 50

local Canvas = {}
Canvas.__index = Canvas

-- `scale` is how many UI units one cell should roughly cover; the real size is
-- snapped to whole screen pixels so cells stay crisp at any UI scale.
function SketchCanvas.Create(parent, scale)
	local self = setmetatable({ scale = scale, pool = {}, rows = {}, dirty = {} }, Canvas)
	local frame = CreateFrame("Frame", nil, parent)
	self.frame = frame

	local paper = frame:CreateTexture(nil, "BACKGROUND")
	paper:SetAllPoints()
	paper:SetColorTexture(unpack(SketchCanvas.PAPER))

	-- Thin Blizzard-style border just outside the paper.
	local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	border:SetPoint("TOPLEFT", -5, 5)
	border:SetPoint("BOTTOMRIGHT", 5, -5)
	border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
	border:SetBackdropBorderColor(0.7, 0.7, 0.7)

	self.grid = Sketch.New()
	return self
end

function Canvas:Layout()
	local _, physicalHeight = GetPhysicalScreenSize()
	local unitsPerPixel = 768 / physicalHeight / self.frame:GetEffectiveScale()
	self.cell = math.max(1, math.floor(self.scale / unitsPerPixel + 0.5)) * unitsPerPixel
	self.frame:SetSize(self.grid.w * self.cell, self.grid.h * self.cell)
	self:RedrawAll()
end

function Canvas:GetSize()
	return self.frame:GetSize()
end

function Canvas:SetGrid(grid)
	self.grid = grid
	self.undo = {}
	if self.cell then self:Layout() end
end

-- Drawing -------------------------------------------------------------------

function Canvas:DrawRow(y)
	local row = self.rows[y]
	if row then
		for i = #row, 1, -1 do
			row[i]:Hide()
			self.pool[#self.pool + 1] = row[i]
			row[i] = nil
		end
	else
		row = {}
		self.rows[y] = row
	end

	local grid, cell = self.grid, self.cell
	local cells, w, base = grid.cells, grid.w, y * grid.w
	local x = 0
	while x < w do
		if cells[base + x + 1] then
			local start = x
			repeat x = x + 1 until x >= w or not cells[base + x + 1]
			local tex = table.remove(self.pool)
			if not tex then
				tex = self.frame:CreateTexture(nil, "ARTWORK")
				tex:SetColorTexture(unpack(SketchCanvas.INK))
			end
			tex:ClearAllPoints()
			tex:SetPoint("TOPLEFT", self.frame, "TOPLEFT", start * cell, -y * cell)
			tex:SetSize((x - start) * cell, cell)
			tex:Show()
			row[#row + 1] = tex
		else
			x = x + 1
		end
	end
end

function Canvas:RedrawAll()
	for y, row in pairs(self.rows) do
		if y >= self.grid.h then
			for i = #row, 1, -1 do
				row[i]:Hide()
				self.pool[#self.pool + 1] = row[i]
			end
			self.rows[y] = nil
		end
	end
	for y = 0, self.grid.h - 1 do self:DrawRow(y) end
	wipe(self.dirty)
end

function Canvas:FlushDirty()
	for y in pairs(self.dirty) do self:DrawRow(y) end
	wipe(self.dirty)
end

-- Editing -------------------------------------------------------------------

-- Turns on mouse drawing. `onChange` runs after every stroke, undo and clear.
function Canvas:EnableEditing(onChange)
	self.onChange = onChange
	self.tool = { mode = "pen", penSize = 3, eraserSize = 3 }
	self.undo = {}
	local frame = self.frame
	frame:EnableMouse(true)
	frame:SetScript("OnMouseDown", function(_, button) self:BeginStroke(button) end)
	frame:SetScript("OnMouseUp", function() self:EndStroke() end)
	frame:SetScript("OnHide", function() self:EndStroke() end)
end

function Canvas:SetTool(mode, size)
	self.tool.mode = mode
	if mode == "pen" then self.tool.penSize = size else self.tool.eraserSize = size end
end

function Canvas:CursorCell()
	local cx, cy = GetCursorPosition()
	local s = self.frame:GetEffectiveScale()
	local x = math.floor((cx / s - self.frame:GetLeft()) / self.cell)
	local y = math.floor((self.frame:GetTop() - cy / s) / self.cell)
	return x, y
end

function Canvas:BeginStroke(button)
	if self.stroke or (button ~= "LeftButton" and button ~= "RightButton") then return end
	local tool = self.tool
	local erase = button == "RightButton" or tool.mode == "eraser"
	local x, y = self:CursorCell()
	self.stroke = {
		button = button,
		ink = not erase,
		size = erase and tool.eraserSize or tool.penSize,
		changes = {},
		x = x,
		y = y,
	}
	Sketch.Stamp(self.grid, x, y, self.stroke.size, self.stroke.ink, self.stroke.changes, self.dirty)
	self:FlushDirty()
	self.frame:SetScript("OnUpdate", function() self:ContinueStroke() end)
end

function Canvas:ContinueStroke()
	local stroke = self.stroke
	if not stroke then return end
	if not IsMouseButtonDown(stroke.button) then
		self:EndStroke()
		return
	end
	local x, y = self:CursorCell()
	if x ~= stroke.x or y ~= stroke.y then
		Sketch.Line(self.grid, stroke.x, stroke.y, x, y, stroke.size, stroke.ink, stroke.changes, self.dirty)
		stroke.x, stroke.y = x, y
		self:FlushDirty()
	end
end

function Canvas:EndStroke()
	local stroke = self.stroke
	if not stroke then return end
	self.stroke = nil
	self.frame:SetScript("OnUpdate", nil)
	if next(stroke.changes) then self:PushUndo(stroke.changes) end
end

function Canvas:PushUndo(changes)
	table.insert(self.undo, changes)
	if #self.undo > UNDO_LIMIT then table.remove(self.undo, 1) end
	if self.onChange then self.onChange() end
end

function Canvas:CanUndo()
	return self.undo and #self.undo > 0
end

function Canvas:Undo()
	local changes = self.undo and table.remove(self.undo)
	if not changes then return end
	Sketch.Revert(self.grid, changes, self.dirty)
	self:FlushDirty()
	if self.onChange then self.onChange() end
end

-- Clearing is one undo step, so it needs no confirmation.
function Canvas:Clear()
	if Sketch.IsEmpty(self.grid) then return end
	local changes = {}
	Sketch.Clear(self.grid, changes)
	self:RedrawAll()
	self:PushUndo(changes)
end

-- Starts over with a blank grid and no history.
function Canvas:Reset()
	self:EndStroke()
	self:SetGrid(Sketch.New())
	if self.onChange then self.onChange() end
end
