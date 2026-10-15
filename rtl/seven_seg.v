`timescale 1ns / 1ps
//
// seven_seg - hex to 7 segment decoder, common cathode so the segments are
// active LOW. Bit order is {a,b,c,d,e,f,g}.
//
// Used three times in the top level: once for the source code and twice for
// the connected load in kW. The pattern table is the usual one, it's also
// printed in the report.
//
module seven_seg (
    input  wire       on,     // 0 blanks the display
    input  wire [3:0] value,  // 0..F
    output reg  [6:0] seg
);

    always @* begin
        if (!on) begin
            seg = 7'b1111111;
        end else begin
            case (value)
                4'h0:    seg = 7'b0000001;
                4'h1:    seg = 7'b1001111;
                4'h2:    seg = 7'b0100100;
                4'h3:    seg = 7'b0001100;
                4'h4:    seg = 7'b1001100;
                4'h5:    seg = 7'b0010010;
                4'h6:    seg = 7'b0010000;
                4'h7:    seg = 7'b0001111;
                4'h8:    seg = 7'b0000000;
                4'h9:    seg = 7'b0000100;
                4'hA:    seg = 7'b0001000;
                4'hB:    seg = 7'b1100000;
                4'hC:    seg = 7'b0110001;
                4'hD:    seg = 7'b1000010;
                4'hE:    seg = 7'b0110000;
                4'hF:    seg = 7'b0111000;
                default: seg = 7'b1111111;
            endcase
        end
    end

endmodule
