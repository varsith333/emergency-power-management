`timescale 1ns / 1ps
//
// alarm_unit - annunciator panel: LEDs plus the audible alarm.
//
// The LEDs are just a decode of source_sel with battery_low and partial_shed
// OR'd in. The buzzer is built out of counters on the clock we already have,
// so no extra hardware is needed:
//
//    battery mode -> intermittent beep
//    blackout     -> continuous tone
//
// TONE_HALF and BEEP_HALF are half periods counted in clock cycles, so they
// scale with the clock and can be dropped right down for simulation.
//
module alarm_unit #(
    parameter TONE_HALF = 25_000,    // half period of the tone, in clocks
    parameter BEEP_HALF = 12_500_000 // half period of the beep envelope, in clocks
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] source_sel,
    input  wire       battery_low,
    input  wire       partial_shed,
    output reg        buzzer,
    output wire       led_mains,
    output wire       led_battery,
    output wire       led_gen,
    output wire       led_blackout,
    output wire       led_low_batt,
    output wire       led_overload
);

    reg [31:0] tone_cnt;
    reg        tone;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tone_cnt <= 32'd0;
            tone     <= 1'b0;
        end else if (tone_cnt >= TONE_HALF - 1) begin
            tone_cnt <= 32'd0;
            tone     <= ~tone;
        end else begin
            tone_cnt <= tone_cnt + 32'd1;
        end
    end

    // slower square wave, used to chop the tone into separate beeps
    reg [31:0] beep_cnt;
    reg        beep_gate;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beep_cnt  <= 32'd0;
            beep_gate <= 1'b0;
        end else if (beep_cnt >= BEEP_HALF - 1) begin
            beep_cnt  <= 32'd0;
            beep_gate <= ~beep_gate;
        end else begin
            beep_cnt <= beep_cnt + 32'd1;
        end
    end

    always @* begin
        case (source_sel)
            2'b01:   buzzer = tone & beep_gate;   // on battery -> beep
            2'b11:   buzzer = tone;               // blackout -> continuous
            default: buzzer = 1'b0;
        endcase
    end

    assign led_mains    = (source_sel == 2'b00);
    assign led_battery  = (source_sel == 2'b01);
    assign led_gen      = (source_sel == 2'b10);
    assign led_blackout = (source_sel == 2'b11);
    assign led_low_batt = battery_low;
    assign led_overload = partial_shed;

endmodule
