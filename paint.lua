local Paint = {}

-- Draws a border over the edges of a widget, after the widget paints
-- itself. Thicknesses must already be scaled by the caller (Cards.sc).
function Paint.addBorder(card, border_color, side_thickness, topbottom_thickness)
    local original_paintTo = card.paintTo

    function card:paintTo(b, x, y)
        original_paintTo(self, b, x, y)

        local dim = self:getSize()

        if dim and dim.w and dim.h then
            local t_side = side_thickness or 4
            local t_tb = topbottom_thickness or 4

            b:paintRect(x, y, dim.w, t_tb, border_color)
            b:paintRect(x, y + dim.h - t_tb, dim.w, t_tb, border_color)
            b:paintRect(x, y, t_side, dim.h, border_color)
            b:paintRect(x + dim.w - t_side, y, t_side, dim.h, border_color)
        end
    end

    return card
end

return Paint