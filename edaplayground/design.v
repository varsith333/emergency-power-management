`timescale 1ns / 1ps

module power_source_manager #(
    parameter MAINS_CAPACITY    = 12,
    parameter GEN_CAPACITY      = 10,
    parameter MAINS_DEBOUNCE    = 8,
    parameter GEN_START_TIMEOUT = 64,
    parameter GEN_COOLDOWN      = 32,
    parameter BAT_RESUME        = 4
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       mains_ok,
    input  wire       gen_ready,
    input  wire       battery_low,
    input  wire [7:0] battery_capacity,
    output reg  [7:0] available_power,
    output reg  [1:0] source_sel,
    output reg        gen_request,
    output wire       emergency,
    output wire [2:0] state_out
);

    localparam [2:0] ST_MAINS = 3'd0,
                     ST_BATT  = 3'd1,
                     ST_GEN   = 3'd2,
                     ST_COOL  = 3'd3,
                     ST_BLACK = 3'd4;

    reg [2:0] state, next_state;

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

    reg [1:0] gen_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) gen_sync <= 2'b00;
        else        gen_sync <= {gen_sync[0], gen_ready};
    end
    wire gen_ready_sync = gen_sync[1];

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

                if (mains_stable)        next_state = ST_MAINS;
                else if (gen_ready_sync) next_state = ST_GEN;
                else if (!battery_low && (battery_capacity >= BAT_RESUME))
                                         next_state = ST_BATT;
            end

            default: next_state = ST_MAINS;
        endcase
    end

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
                available_power = MAINS_CAPACITY;
                source_sel      = 2'b00;
                gen_request     = 1'b1;
            end
            ST_BLACK: begin
                available_power = 8'd0;
                source_sel      = 2'b11;
                gen_request     = 1'b1;
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

`timescale 1ns / 1ps

module priority_scheduler (
    input  wire [7:0]  available_power,
    input  wire [47:0] load_demand,
    output reg  [5:0]  grant,
    output reg  [7:0]  total_granted,
    output reg  [7:0]  total_demand,
    output wire        partial_shed
);

    wire [7:0] d1 = load_demand[7:0];
    wire [7:0] d2 = load_demand[15:8];
    wire [7:0] d3 = load_demand[23:16];
    wire [7:0] d4 = load_demand[31:24];
    wire [7:0] d5 = load_demand[39:32];
    wire [7:0] d6 = load_demand[47:40];

    reg [7:0] cum;
    reg       blocked;

    always @* begin
        cum     = 8'd0;
        blocked = 1'b0;
        grant   = 6'b000000;

        if (!blocked && ((cum + d1) <= available_power)) begin
            grant[0] = 1'b1;
            cum      = cum + d1;
        end else blocked = 1'b1;

        if (!blocked && ((cum + d2) <= available_power)) begin
            grant[1] = 1'b1;
            cum      = cum + d2;
        end else blocked = 1'b1;

        if (!blocked && ((cum + d3) <= available_power)) begin
            grant[2] = 1'b1;
            cum      = cum + d3;
        end else blocked = 1'b1;

        if (!blocked && ((cum + d4) <= available_power)) begin
            grant[3] = 1'b1;
            cum      = cum + d4;
        end else blocked = 1'b1;

        if (!blocked && ((cum + d5) <= available_power)) begin
            grant[4] = 1'b1;
            cum      = cum + d5;
        end else blocked = 1'b1;

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

`timescale 1ns / 1ps

module load_controller #(
    parameter LOAD_STEP = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [5:0]  grant,
    input  wire [47:0] load_demand,
    output reg  [5:0]  load_on,
    output reg  [7:0]  total_connected,
    output wire        energising
);

    reg [15:0] step_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_on  <= 6'b000000;
            step_cnt <= 16'd0;
        end else begin

            if (!grant[0]) load_on[0] <= 1'b0;
            if (!grant[1]) load_on[1] <= 1'b0;
            if (!grant[2]) load_on[2] <= 1'b0;
            if (!grant[3]) load_on[3] <= 1'b0;
            if (!grant[4]) load_on[4] <= 1'b0;
            if (!grant[5]) load_on[5] <= 1'b0;

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

`timescale 1ns / 1ps

module alarm_unit #(
    parameter TONE_HALF = 25_000,
    parameter BEEP_HALF = 12_500_000
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
            2'b01:   buzzer = tone & beep_gate;
            2'b11:   buzzer = tone;
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

`timescale 1ns / 1ps

module seven_seg (
    input  wire       on,
    input  wire [3:0] value,
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

`timescale 1ns / 1ps

module epms_top #(
    parameter MAINS_CAPACITY    = 12,
    parameter GEN_CAPACITY      = 10,
    parameter MAINS_DEBOUNCE    = 8,
    parameter GEN_START_TIMEOUT = 64,
    parameter GEN_COOLDOWN      = 32,
    parameter BAT_RESUME        = 4,
    parameter LOAD_STEP         = 8,
    parameter TONE_HALF         = 25_000,
    parameter BEEP_HALF         = 12_500_000,

    parameter DEMAND_L1         = 8'd2,
    parameter DEMAND_L2         = 8'd1,
    parameter DEMAND_L3         = 8'd1,
    parameter DEMAND_L4         = 8'd1,
    parameter DEMAND_L5         = 8'd2,
    parameter DEMAND_L6         = 8'd3
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       mains_ok,
    input  wire       gen_ready,
    input  wire       battery_low,
    input  wire [7:0] battery_capacity,

    output wire [5:0] load_on,
    output wire       gen_request,

    output wire [1:0] source_sel,
    output wire [7:0] available_power,
    output wire [7:0] total_connected,
    output wire       partial_shed,
    output wire       emergency,
    output wire       energising,
    output wire [2:0] state_out,

    output wire       buzzer,
    output wire       led_mains,
    output wire       led_battery,
    output wire       led_gen,
    output wire       led_blackout,
    output wire       led_low_batt,
    output wire       led_overload,

    output wire [6:0] seg_mode,
    output wire [6:0] seg_tens,
    output wire [6:0] seg_ones
);

    localparam [47:0] LOAD_DEMAND = {DEMAND_L6, DEMAND_L5, DEMAND_L4,
                                     DEMAND_L3, DEMAND_L2, DEMAND_L1};

    wire [5:0] grant;
    wire [7:0] total_granted;
    wire [7:0] total_demand;

    power_source_manager #(
        .MAINS_CAPACITY    (MAINS_CAPACITY),
        .GEN_CAPACITY      (GEN_CAPACITY),
        .MAINS_DEBOUNCE    (MAINS_DEBOUNCE),
        .GEN_START_TIMEOUT (GEN_START_TIMEOUT),
        .GEN_COOLDOWN      (GEN_COOLDOWN),
        .BAT_RESUME        (BAT_RESUME)
    ) u_psm (
        .clk              (clk),
        .rst_n            (rst_n),
        .mains_ok         (mains_ok),
        .gen_ready        (gen_ready),
        .battery_low      (battery_low),
        .battery_capacity (battery_capacity),
        .available_power  (available_power),
        .source_sel       (source_sel),
        .gen_request      (gen_request),
        .emergency        (emergency),
        .state_out        (state_out)
    );

    priority_scheduler u_sched (
        .available_power (available_power),
        .load_demand     (LOAD_DEMAND),
        .grant           (grant),
        .total_granted   (total_granted),
        .total_demand    (total_demand),
        .partial_shed    (partial_shed)
    );

    load_controller #(
        .LOAD_STEP (LOAD_STEP)
    ) u_lctl (
        .clk              (clk),
        .rst_n            (rst_n),
        .grant            (grant),
        .load_demand      (LOAD_DEMAND),
        .load_on          (load_on),
        .total_connected  (total_connected),
        .energising       (energising)
    );

    alarm_unit #(
        .TONE_HALF (TONE_HALF),
        .BEEP_HALF (BEEP_HALF)
    ) u_alarm (
        .clk          (clk),
        .rst_n        (rst_n),
        .source_sel   (source_sel),
        .battery_low  (battery_low),
        .partial_shed (partial_shed),
        .buzzer       (buzzer),
        .led_mains    (led_mains),
        .led_battery  (led_battery),
        .led_gen      (led_gen),
        .led_blackout (led_blackout),
        .led_low_batt (led_low_batt),
        .led_overload (led_overload)
    );

    seven_seg u_seg_mode (
        .on    (1'b1),
        .value ({2'b00, source_sel}),
        .seg   (seg_mode)
    );

    wire [7:0] ones_raw = total_connected % 8'd10;
    wire [7:0] tens_raw = total_connected / 8'd10;

    seven_seg u_seg_tens (
        .on    (1'b1),
        .value (tens_raw[3:0]),
        .seg   (seg_tens)
    );

    seven_seg u_seg_ones (
        .on    (1'b1),
        .value (ones_raw[3:0]),
        .seg   (seg_ones)
    );

endmodule
