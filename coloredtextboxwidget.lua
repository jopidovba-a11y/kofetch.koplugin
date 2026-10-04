local Blitbuffer = require("ffi/blitbuffer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local RenderText = require("ui/rendertext")
local Screen = require("device").screen

local ColoredTextBoxWidget = TextBoxWidget:extend{
    line_colors = nil,
}

function ColoredTextBoxWidget:_renderText(start_row_idx, end_row_idx)
    if start_row_idx < 1 then start_row_idx = 1 end
    if end_row_idx > #self.vertical_string_list then
        end_row_idx = #self.vertical_string_list
    end

    local row_count = end_row_idx == 0 and 1 or end_row_idx - start_row_idx + 1

    local h = self.height or self.line_height_px * row_count
    h = h + self.line_glyph_extra_height

    if self._bb then
        self._bb:free()
    end

    local bbtype = nil
    local color_fg = not Blitbuffer.isColor8(self.fgcolor)
    local color_bg = not Blitbuffer.isColor8(self.bgcolor)

    if (self.line_num_to_image and self.line_num_to_image[start_row_idx])
        or color_fg or color_bg then

        bbtype = Screen:isColorEnabled()
            and Blitbuffer.TYPE_BBRGB32
            or Blitbuffer.TYPE_BB8
    end

    self._bb = Blitbuffer.new(self.width, h, bbtype)

    if not color_bg then
        self._bb:fill(self.bgcolor)
    else
        self._bb:paintRectRGB32(
            0,
            0,
            self._bb:getWidth(),
            self._bb:getHeight(),
            self.bgcolor
        )
    end

    local y = self.line_glyph_baseline

    if self.use_xtext then
        for i = start_row_idx, end_row_idx do

            local line = self.vertical_string_list[i]

            if self.line_with_ellipsis
                and i == self.line_with_ellipsis
                and not line.ellipsis_added then

                local ellipsis_width =
                    RenderText:getEllipsisWidth(self.face)

                line.width = line.width + ellipsis_width

                if line.width > line.targeted_width then
                    line = self._xtext:makeLine(
                        line.offset,
                        line.targeted_width - ellipsis_width,
                        false,
                        self._tabstop_width
                    )

                    self.vertical_string_list[i] = line
                end

                if line.end_offset
                    and line.end_offset < #self._xtext then

                    line.end_offset = line.end_offset + 1
                    line.idx_to_substitute_with_ellipsis =
                        line.end_offset
                end

                line.ellipsis_added = true
            end

            self:_shapeLine(line)

            if line.xglyphs then
                for _, xglyph in ipairs(line.xglyphs) do

                    if not xglyph.no_drawing then

                        local face =
                            self.face.getFallbackFont(xglyph.font_num)

                        local bolder =
                            self._ptf_char_is_bold
                            and self._ptf_char_is_bold[xglyph.text_index]
                            or false

                        local glyph =
                            RenderText:getGlyphByIndex(
                                face,
                                xglyph.glyph,
                                self.bold,
                                bolder
                            )

                        -- Only difference from the original:
                        -- choose a color for this line.
                        local color = self.fgcolor

                        if self.line_colors
                            and self.line_colors[i] then
                            color = self.line_colors[i]
                        end

                        if self._alt_color_for_rtl then
                            color =
                                xglyph.is_rtl
                                and Blitbuffer.COLOR_DARK_GRAY
                                or Blitbuffer.COLOR_BLACK
                        end

                        if not color_fg then
                            self._bb:colorblitFrom(
                                glyph.bb,
                                xglyph.x0 + glyph.l + xglyph.x_offset,
                                y - glyph.t - xglyph.y_offset,
                                0,
                                0,
                                glyph.bb:getWidth(),
                                glyph.bb:getHeight(),
                                color
                            )
                        else
                            self._bb:colorblitFromRGB32(
                                glyph.bb,
                                xglyph.x0 + glyph.l + xglyph.x_offset,
                                y - glyph.t - xglyph.y_offset,
                                0,
                                0,
                                glyph.bb:getWidth(),
                                glyph.bb:getHeight(),
                                color
                            )
                        end
                    end
                end
            end

            y = y + self.line_height_px
        end

        self:_renderImage(start_row_idx)

        if self.highlight_rects then
            for _, rect in ipairs(self.highlight_rects) do
                self._bb:darkenRect(
                    rect.x,
                    rect.y,
                    rect.w,
                    rect.h,
                    self.highlight_lighten_factor
                )
            end
        end

        return
    end

    -- Only when not self.use_xtext:

    for i = start_row_idx, end_row_idx do

        local line = self.vertical_string_list[i]

        local pen_x = 0

        if self.alignment == "center" then
            pen_x = (self.width - line.width) / 2 or 0
        elseif self.alignment == "right" then
            pen_x = self.width - line.width
        end

        local line_text = self:_getLineText(line)

        if self.line_with_ellipsis and i == self.line_with_ellipsis then

            local ellipsis_width =
                RenderText:getEllipsisWidth(
                    self.face,
                    self.bold
                )

            if line.width + ellipsis_width > self.width then
                line_text =
                    RenderText:truncateTextByWidth(
                        line_text,
                        self.face,
                        self.width,
                        true,
                        self.bold
                    )
            else
                line_text = line_text .. "…"
            end
        end

        -- Only difference from the original:
        -- choose a color for this line.
        local color = self.fgcolor

        if self.line_colors
            and self.line_colors[i] then
            color = self.line_colors[i]
        end

        RenderText:renderUtf8Text(
            self._bb,
            pen_x,
            y,
            self.face,
            line_text,
            true,
            self.bold,
            color,
            nil,
            self:_getLinePads(line)
        )

        y = y + self.line_height_px
    end

    self:_renderImage(start_row_idx)

    if self.highlight_rects then
        for _, rect in ipairs(self.highlight_rects) do
            self._bb:darkenRect(
                rect.x,
                rect.y,
                rect.w,
                rect.h,
                self.highlight_lighten_factor
            )
        end
    end
end

return ColoredTextBoxWidget