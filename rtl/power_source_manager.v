`timescale 1ns / 1ps
//
// power_source_manager
//
// Works out which source is feeding the loads and how much power it can
// actually give us. Switchover FSM:
//
//    MAINS --fails--> BATTERY --gen ready--> GENERATOR --mains back-->
//    COOLDOWN (gen idles a while) --> MAINS
//    BATTERY --battery low and gen never started--> BLACKOUT
//
// mains_ok and gen_ready come off the board so they get synchronised, and
// mains is debounced as well (MAINS_DEBOUNCE clocks) so a short dip doesn't
// drop the whole installation. battery_capacity is an input so the testbench
// can vary how much we have to work with - we only offer half of it while
// battery_low is set, since that's the reserve we're not supposed to touch.
//
module power_source_manager #(
    parameter MAINS_CAPACITY    = 12,   // kW when running on mains
    parameter GEN_CAPACITY      = 10,   // kW from the generator
    parameter MAINS_DEBOUNCE    = 8,    // clocks mains must hold before we react
    parameter GEN_START_TIMEOUT = 64,   // clocks on battery before blackout
    parameter GEN_COOLDOWN      = 32,   // clocks gen keeps running after mains returns
    parameter BAT_RESUME        = 4     // kW of battery needed to leave blackout
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       mains_ok,
    input  wire       gen_ready,
    input  wire       battery_low,
    input  wire [7:0] battery_capacity,
    output reg  [7:0] available_power,   // kW handed over to the scheduler
    output reg  [1:0] source_sel,        // 0=mains 1=batt 2=gen 3=blackout
    output reg        gen_request,       // auto-start command
    output wire       emergency,
    output wire [2:0] state_out          // handy on the waveform
);

    localparam [2:0] ST_MAINS = 3'd0,
                     ST_BATT  = 3'd1,
                     ST_GEN   = 3'd2,
                     ST_COOL  = 3'd3,
                     ST_BLACK = 3'd4;

    reg [2:0] state, next_state;

    // ------------------------------------------------------------------
    // synchronise + debounce mains
    // ------------------------------------------------------------------
    reg [1:0]  mains_sync;
    reg        mains_stable;
    reg [15:0] deb_cnt;

    wire mains_synced = mains_sync[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mains_sync   <= 2'b11;
            mains_stable <= 1'b1;
            deb_cnt      <= 16'd0;
        end else begin
            mains_sync <= {mains_sync[0], mains_ok};
            if (mains_synced == mains_stable) begin
                deb_cnt <= 16'd0;
            end else if (deb_cnt >= MAINS_DEBOUNCE - 1) begin
                mains_stable <= mains_synced;
                deb_cnt      <= 16'd0;
            end else begin
                deb_cnt <= deb_cnt + 16'd1;
            end
        end
    end

    // gen ready only needs the sync flops, it's already a clean signal
    reg [1:0] gen_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) gen_sync <= 2'b00;
        else        gen_sync <= {gen_sync[0], gen_ready};
    end
    wire gen_ready_sync = gen_sync[1];

    // two timers: how long we wait for the gen, and how long it runs on after
    // mains comes back
    reg [15:0] tmo_cnt;
    reg [15:0] cool_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmo_cnt  <= 16'd0;
            cool_cnt <= 16'd0;
        end else begin
            if (state == ST_BATT) begin
                if (tmo_cnt < GEN_START_TIMEOUT - 1) tmo_cnt <= tmo_cnt + 16'd1;
            end else begin
                tmo_cnt <= 16'd0;
            end

            if (state == ST_COOL) begin
                if (cool_cnt < GEN_COOLDOWN - 1) cool_cnt <= cool_cnt + 16'd1;
            end else begin
                cool_cnt <= 16'd0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= ST_MAINS;
        else        state <= next_state;
    end

    always @* begin
        next_state = state;
        case (state)
            ST_MAINS: begin
                if (!mains_stable) next_state = ST_BATT;
            end

            ST_BATT: begin
                if (mains_stable)        next_state = ST_MAINS;
                else if (gen_ready_sync) next_state = ST_GEN;
                // we've waited long enough and the gen still isn't up
                else if (battery_low && (tmo_cnt >= GEN_START_TIMEOUT - 1))
                                         next_state = ST_BLACK;
            end

            ST_GEN: begin
                if (mains_stable) next_state = ST_COOL;
            end

            ST_COOL: begin
                if (!mains_stable)               next_state = ST_BATT;
                else if (cool_cnt >= GEN_COOLDOWN - 1) next_state = ST_MAINS;
            end

            ST_BLACK: begin
                // three ways out of this: mains comes back, the gen finally
                // cranks, or the battery recovers by itself
                if (mains_stable)        next_state = ST_MAINS;
                else if (gen_ready_sync) next_state = ST_GEN;
                else if (!battery_low && (battery_capacity >= BAT_RESUME))
                                         next_state = ST_BATT;
            end

            default: next_state = ST_MAINS;
        endcase
    end

    // Moore outputs. Everything is a constant here apart from the battery,
    // which we derate when battery_low is asserted.
    always @* begin
        case (state)
            ST_MAINS: begin
                available_power = MAINS_CAPACITY;
                source_sel      = 2'b00;
                gen_request     = 1'b0;
            end
            ST_BATT: begin
                available_power = battery_low ? (battery_capacity >> 1) : battery_capacity;
                source_sel      = 2'b01;
                gen_request     = 1'b1;
            end
            ST_GEN: begin
                available_power = GEN_CAPACITY;
                source_sel      = 2'b10;
                gen_request     = 1'b1;
            end
            ST_COOL: begin
                available_power = MAINS_CAPACITY;   // loads already back on mains
                source_sel      = 2'b00;
                gen_request     = 1'b1;             // still spinning down
            end
            ST_BLACK: begin
                available_power = 8'd0;
                source_sel      = 2'b11;
                gen_request     = 1'b1;             // keep trying to crank it
            end
            default: begin
                available_power = 8'd0;
                source_sel      = 2'b11;
                gen_request     = 1'b0;
            end
        endcase
    end

    assign emergency = (state != ST_MAINS) && (state != ST_COOL);
    assign state_out = state;

endmodule
