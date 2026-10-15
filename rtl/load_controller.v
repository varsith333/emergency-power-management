`timescale 1ns / 1ps
//
// load_controller - turns the scheduler's grant vector into real contactors.
//
// Shedding is immediate: the clock we notice a grant is gone, the load is off.
// Safety first, and the testbench relies on that being only one clock.
//
// Restoring is the other way round - one load every LOAD_STEP clocks, highest
// priority first. That's how you'd limit inrush current on a real feeder, and
// it also makes the rebuild sequence easy to see on the waveform.
//
module load_controller #(
    parameter LOAD_STEP = 8    // clocks between two turn-on steps
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [5:0]  grant,
    input  wire [47:0] load_demand,   // 6 x 8-bit demands in kW
    output reg  [5:0]  load_on,
    output reg  [7:0]  total_connected,
    output wire        energising     // 1 = rebuild still in progress
);

    reg [15:0] step_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_on  <= 6'b000000;
            step_cnt <= 16'd0;
        end else begin
            // shed first, no delay
            if (!grant[0]) load_on[0] <= 1'b0;
            if (!grant[1]) load_on[1] <= 1'b0;
            if (!grant[2]) load_on[2] <= 1'b0;
            if (!grant[3]) load_on[3] <= 1'b0;
            if (!grant[4]) load_on[4] <= 1'b0;
            if (!grant[5]) load_on[5] <= 1'b0;

            // then bring them back one at a time
            if (step_cnt >= LOAD_STEP - 1) begin
                step_cnt <= 16'd0;
                if      (grant[0] && !load_on[0]) load_on[0] <= 1'b1;
                else if (grant[1] && !load_on[1]) load_on[1] <= 1'b1;
                else if (grant[2] && !load_on[2]) load_on[2] <= 1'b1;
                else if (grant[3] && !load_on[3]) load_on[3] <= 1'b1;
                else if (grant[4] && !load_on[4]) load_on[4] <= 1'b1;
                else if (grant[5] && !load_on[5]) load_on[5] <= 1'b1;
            end else begin
                step_cnt <= step_cnt + 16'd1;
            end
        end
    end

    // what the installation is actually drawing right now
    always @* begin
        total_connected = 8'd0;
        if (load_on[0]) total_connected = total_connected + load_demand[7:0];
        if (load_on[1]) total_connected = total_connected + load_demand[15:8];
        if (load_on[2]) total_connected = total_connected + load_demand[23:16];
        if (load_on[3]) total_connected = total_connected + load_demand[31:24];
        if (load_on[4]) total_connected = total_connected + load_demand[39:32];
        if (load_on[5]) total_connected = total_connected + load_demand[47:40];
    end

    assign energising = (load_on != grant);

endmodule
