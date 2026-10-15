`timescale 1ns / 1ps
//
// priority_scheduler - purely combinational, no clock.
//
// Walks the load list from the top (L1 = most important), accumulating demand
// as it goes, and stops as soon as the next one no longer fits. The granted
// set therefore always comes out as a prefix of the priority list.
//
// The 'blocked' flag is what makes this strict priority rather than
// best-fit: once a load is refused, everything below it is refused too, even
// if it would have fitted on its own. Without it a low priority load could
// grab power that a waiting high priority load still needs.
//
//   avail = 5 kW, demands = 2,1,1,1,2,3  ->  grant = 001111 (exactly 5 kW)
//
module priority_scheduler (
    input  wire [7:0]  available_power,   // kW we've been given
    input  wire [47:0] load_demand,       // L1 in [7:0] ... L6 in [47:40]
    output reg  [5:0]  grant,             // grant[i] = load i+1 may run
    output reg  [7:0]  total_granted,
    output reg  [7:0]  total_demand,
    output wire        partial_shed       // 1 = something is being shed
);

    wire [7:0] d1 = load_demand[7:0];
    wire [7:0] d2 = load_demand[15:8];
    wire [7:0] d3 = load_demand[23:16];
    wire [7:0] d4 = load_demand[31:24];
    wire [7:0] d5 = load_demand[39:32];
    wire [7:0] d6 = load_demand[47:40];

    reg [7:0] cum;      // running total of what we've already promised out
    reg       blocked;

    always @* begin
        cum     = 8'd0;
        blocked = 1'b0;
        grant   = 6'b000000;

        // L1 - medical / life support
        if (!blocked && ((cum + d1) <= available_power)) begin
            grant[0] = 1'b1;
            cum      = cum + d1;
        end else blocked = 1'b1;

        // L2 - control & communication
        if (!blocked && ((cum + d2) <= available_power)) begin
            grant[1] = 1'b1;
            cum      = cum + d2;
        end else blocked = 1'b1;

        // L3 - emergency lighting
        if (!blocked && ((cum + d3) <= available_power)) begin
            grant[2] = 1'b1;
            cum      = cum + d3;
        end else blocked = 1'b1;

        // L4 - security
        if (!blocked && ((cum + d4) <= available_power)) begin
            grant[3] = 1'b1;
            cum      = cum + d4;
        end else blocked = 1'b1;

        // L5 - water pump
        if (!blocked && ((cum + d5) <= available_power)) begin
            grant[4] = 1'b1;
            cum      = cum + d5;
        end else blocked = 1'b1;

        // L6 - HVAC, lowest priority so it goes first when power is short
        if (!blocked && ((cum + d6) <= available_power)) begin
            grant[5] = 1'b1;
            cum      = cum + d6;
        end else blocked = 1'b1;

        total_granted = cum;
    end

    always @* begin
        total_demand = d1 + d2 + d3 + d4 + d5 + d6;
    end

    assign partial_shed = (total_granted != total_demand);

endmodule
