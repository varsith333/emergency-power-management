`timescale 1ns / 1ps
//
// tb_epms_top
//
// Runs a full emergency scenario against the whole system and checks the
// result. Two safety properties are watched on every clock:
//
//   P1  the running loads never draw more than the active source can supply
//   P2  the running loads are always a prefix of the priority list, so a
//       lower priority load is never up while a higher one is down
//
// Directed checks print [PASS]/[FAIL], summary at the end.
//
module tb_epms_top;

    // Timing values are small so the sim stays fast. On a real 100 MHz part
    // they'd be roughly 1000x bigger.
    localparam MAINS_CAPACITY    = 12;
    localparam GEN_CAPACITY      = 10;
    localparam MAINS_DEBOUNCE    = 8;
    localparam GEN_START_TIMEOUT = 64;
    localparam GEN_COOLDOWN      = 32;
    localparam BAT_RESUME        = 4;
    localparam LOAD_STEP         = 8;
    localparam TONE_HALF         = 4;
    localparam BEEP_HALF         = 32;

    // long enough for all six loads to come back, worst case
    localparam SETTLE = 6*LOAD_STEP + 16;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         mains_ok = 1'b1;
    reg         gen_ready = 1'b0;
    reg         battery_low = 1'b0;
    reg  [7:0]  battery_capacity = 8'd8;

    wire [5:0]  load_on;
    wire        gen_request;
    wire [1:0]  source_sel;
    wire [7:0]  available_power;
    wire [7:0]  total_connected;
    wire        partial_shed;
    wire        emergency;
    wire        energising;
    wire [2:0]  state_out;
    wire        buzzer;
    wire        led_mains, led_battery, led_gen, led_blackout, led_low_batt, led_overload;
    wire [6:0]  seg_mode, seg_tens, seg_ones;

    epms_top #(
        .MAINS_CAPACITY    (MAINS_CAPACITY),
        .GEN_CAPACITY      (GEN_CAPACITY),
        .MAINS_DEBOUNCE    (MAINS_DEBOUNCE),
        .GEN_START_TIMEOUT (GEN_START_TIMEOUT),
        .GEN_COOLDOWN      (GEN_COOLDOWN),
        .BAT_RESUME        (BAT_RESUME),
        .LOAD_STEP         (LOAD_STEP),
        .TONE_HALF         (TONE_HALF),
        .BEEP_HALF         (BEEP_HALF)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .mains_ok         (mains_ok),
        .gen_ready        (gen_ready),
        .battery_low      (battery_low),
        .battery_capacity (battery_capacity),
        .load_on          (load_on),
        .gen_request      (gen_request),
        .source_sel       (source_sel),
        .available_power  (available_power),
        .total_connected  (total_connected),
        .partial_shed     (partial_shed),
        .emergency        (emergency),
        .energising       (energising),
        .state_out        (state_out),
        .buzzer           (buzzer),
        .led_mains        (led_mains),
        .led_battery      (led_battery),
        .led_gen          (led_gen),
        .led_blackout     (led_blackout),
        .led_low_batt     (led_low_batt),
        .led_overload     (led_overload),
        .seg_mode         (seg_mode),
        .seg_tens         (seg_tens),
        .seg_ones         (seg_ones)
    );

    always #5 clk = ~clk;   // 100 MHz

    integer checks = 0;
    integer errors = 0;

    task check_eq8;
        input [8*40:1] label;
        input [7:0]    got;
        input [7:0]    exp;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("[FAIL] %0t : %0s : got %0d, expected %0d", $time, label, got, exp);
            end else begin
                $display("[PASS] %0t : %0s = %0d", $time, label, got);
            end
        end
    endtask

    task check_eq6;
        input [8*40:1] label;
        input [5:0]    got;
        input [5:0]    exp;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("[FAIL] %0t : %0s : got %b, expected %b", $time, label, got, exp);
            end else begin
                $display("[PASS] %0t : %0s = %b", $time, label, got);
            end
        end
    endtask

    task check_bit;
        input [8*40:1] label;
        input          got;
        input          exp;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("[FAIL] %0t : %0s : got %b, expected %b", $time, label, got, exp);
            end else begin
                $display("[PASS] %0t : %0s = %b", $time, label, got);
            end
        end
    endtask

    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    // P1/P2 run on every clock, not just at the checkpoints below
    // ------------------------------------------------------------------
    reg [7:0] avail_prev = 8'hFF;
    integer   buzz_seen;

    always @(posedge clk) begin
        if (rst_n) begin
            avail_prev <= available_power;

            // P1. Skipped in the single clock where availability itself just
            // changed, because shedding takes one clock to catch up.
            if (available_power === avail_prev) begin
                if (total_connected > available_power) begin
                    errors = errors + 1;
                    $display("[FAIL] %0t : P1 VIOLATION : consumed %0d kW > available %0d kW",
                             $time, total_connected, available_power);
                end
            end

            // P2 - load n only allowed if load n-1 is on
            if (load_on[1] && !load_on[0]) begin
                errors = errors + 1;
                $display("[FAIL] %0t : P2 VIOLATION : LOAD2 running while LOAD1 off", $time);
            end
            if (load_on[2] && !load_on[1]) begin
                errors = errors + 1;
                $display("[FAIL] %0t : P2 VIOLATION : LOAD3 running while LOAD2 off", $time);
            end
            if (load_on[3] && !load_on[2]) begin
                errors = errors + 1;
                $display("[FAIL] %0t : P2 VIOLATION : LOAD4 running while LOAD3 off", $time);
            end
            if (load_on[4] && !load_on[3]) begin
                errors = errors + 1;
                $display("[FAIL] %0t : P2 VIOLATION : LOAD5 running while LOAD4 off", $time);
            end
            if (load_on[5] && !load_on[4]) begin
                errors = errors + 1;
                $display("[FAIL] %0t : P2 VIOLATION : LOAD6 running while LOAD5 off", $time);
            end
        end
    end

    initial begin
        $timeformat(-9, 0, " ns", 10);
        $display("=================================================================");
        $display(" DIGITAL EMERGENCY POWER MANAGEMENT SYSTEM - regression start");
        $display("=================================================================");

        // hold in reset for a few clocks
        rst_n              = 1'b0;
        mains_ok           = 1'b1;
        gen_ready          = 1'b0;
        battery_low        = 1'b0;
        battery_capacity   = 8'd8;
        wait_cycles(5);
        rst_n = 1'b1;

        // ---- 1) everything healthy on mains -------------------------------
        $display("--- SCENARIO 1 : normal operation on mains ---------------------");
        wait_cycles(SETTLE);
        check_eq8("S1 available power [kW]",  available_power,  MAINS_CAPACITY);
        check_eq6("S1 all six loads on",      load_on,          6'b111111);
        check_eq8("S1 total connected [kW]",  total_connected,  8'd10);
        check_bit("S1 generator stopped",     gen_request,      1'b0);
        check_eq8("S1 source code (0=MAINS)", {6'b0, source_sel}, 8'd0);
        check_bit("S1 no partial shedding",   partial_shed,     1'b0);
        check_bit("S1 alarm silent",          buzzer,           1'b0);

        // ---- 2) mains goes away ------------------------------------------
        $display("--- SCENARIO 2 : mains failure, emergency on battery -----------");
        mains_ok = 1'b0;
        wait_cycles(MAINS_DEBOUNCE + 8);
        check_eq8("S2 source code (1=BATT)",  {6'b0, source_sel}, 8'd1);
        check_bit("S2 generator auto-start", gen_request,      1'b1);
        check_bit("S2 emergency flag",       emergency,        1'b1);
        // battery = 8 kW, L1..L5 come to 7 kW so L6 (3 kW) is the odd one out
        check_eq6("S2 loads L1..L5 kept",    load_on,          6'b011111);
        check_eq8("S2 total connected [kW]", total_connected,  8'd7);
        check_bit("S2 overload LED on",      led_overload,     1'b1);
        check_bit("S2 battery LED on",       led_battery,      1'b1);

        // ---- 3) generator picks up the load ------------------------------
        $display("--- SCENARIO 3 : generator ready, loads restored in order -----");
        wait_cycles(20);
        gen_ready = 1'b1;
        wait_cycles(4 + SETTLE);
        check_eq8("S3 source code (2=GEN)",   {6'b0, source_sel}, 8'd2);
        // gen is 10 kW, same as total demand, so everything should come back
        check_eq6("S3 all six loads back",   load_on,          6'b111111);
        check_eq8("S3 total connected [kW]", total_connected,  8'd10);
        check_bit("S3 no partial shedding",  partial_shed,     1'b0);
        check_bit("S3 generator still on",   gen_request,      1'b1);

        // ---- 4) mains returns, gen idles before stopping -----------------
        $display("--- SCENARIO 4 : mains restored, generator cool-down ----------");
        mains_ok = 1'b1;
        wait_cycles(MAINS_DEBOUNCE + 4);
        check_eq8("S4 back on mains (0)",    {6'b0, source_sel}, 8'd0);
        check_bit("S4 gen runs cool-down",   gen_request,      1'b1);
        check_eq6("S4 all loads still on",   load_on,          6'b111111);
        wait_cycles(GEN_COOLDOWN + 8);
        check_bit("S4 generator stopped",    gen_request,      1'b0);
        gen_ready = 1'b0;   // the set has actually shut down now

        // ---- 5) short dip on mains, debounce should eat it ---------------
        $display("--- SCENARIO 5 : 3-cycle mains glitch is debounced -----------");
        mains_ok = 1'b0;
        wait_cycles(3);
        mains_ok = 1'b1;
        wait_cycles(MAINS_DEBOUNCE + 8);
        check_eq8("S5 still on mains",       {6'b0, source_sel}, 8'd0);
        check_eq6("S5 no load disturbed",    load_on,          6'b111111);
        check_bit("S5 no gen start",         gen_request,      1'b0);

        // ---- 6) second failure, battery runs down ------------------------
        $display("--- SCENARIO 6 : mains fail, battery 5 kW, then battery low ---");
        battery_capacity = 8'd5;
        mains_ok         = 1'b0;
        wait_cycles(MAINS_DEBOUNCE + 8);
        check_eq8("S6 source code (1=BATT)", {6'b0, source_sel}, 8'd1);
        // 5 kW exactly covers L1+L2+L3+L4
        check_eq6("S6 loads L1..L4 kept",    load_on,          6'b001111);
        check_eq8("S6 total connected [kW]", total_connected,  8'd5);

        battery_low = 1'b1;
        wait_cycles(4);
        check_bit("S6 low-battery LED",      led_low_batt,     1'b1);
        // reserve halves it to 2 kW, only the medical load survives that
        check_eq6("S6 only LOAD1 survives",  load_on,          6'b000001);
        check_eq8("S6 total connected [kW]", total_connected,  8'd2);

        // ---- 7) gen never starts and the battery gives out ---------------
        $display("--- SCENARIO 7 : generator timeout + dead battery = blackout --");
        wait_cycles(GEN_START_TIMEOUT + 8);
        check_eq8("S7 source code (3=BLACK)", {6'b0, source_sel}, 8'd3);
        check_eq8("S7 no power available",    available_power, 8'd0);
        check_eq6("S7 every load shed",       load_on,         6'b000000);
        check_eq8("S7 total connected [kW]",  total_connected, 8'd0);
        // blackout should be a continuous tone, watch a couple of periods
        buzz_seen = 0;
        repeat (2*TONE_HALF) begin
            @(posedge clk);
            if (buzzer) buzz_seen = buzz_seen + 1;
        end
        check_bit("S7 blackout tone sounding", (buzz_seen > 0), 1'b1);

        // ---- 8) gen finally catches --------------------------------------
        $display("--- SCENARIO 8 : generator starts, loads rebuilt by priority --");
        battery_capacity = 8'd5;
        battery_low      = 1'b0;
        gen_ready        = 1'b1;
        wait_cycles(4 + SETTLE);
        check_eq8("S8 source code (2=GEN)",   {6'b0, source_sel}, 8'd2);
        check_eq6("S8 all six loads back",    load_on,          6'b111111);
        check_eq8("S8 total connected [kW]",  total_connected,  8'd10);

        // ---- 9) back to normal -------------------------------------------
        $display("--- SCENARIO 9 : mains restored, back to normal --------------");
        mains_ok = 1'b1;
        wait_cycles(MAINS_DEBOUNCE + GEN_COOLDOWN + 8);
        gen_ready = 1'b0;
        wait_cycles(8);
        check_eq8("S9 source code (0=MAINS)", {6'b0, source_sel}, 8'd0);
        check_eq6("S9 all six loads on",      load_on,          6'b111111);
        check_bit("S9 generator stopped",     gen_request,      1'b0);
        check_bit("S9 alarm silent",          buzzer,           1'b0);
        check_bit("S9 no emergency",          emergency,        1'b0);

        $display("=================================================================");
        $display(" CHECKS RUN : %0d", checks);
        $display(" ERRORS     : %0d", errors);
        if (errors == 0)
            $display(" RESULT     : **** ALL TESTS PASSED ****");
        else
            $display(" RESULT     : **** %0d TEST(S) FAILED ****", errors);
        $display("=================================================================");
        $finish;
    end

    // in case something hangs we still want to know
    initial begin
        #200_000;
        $display("[FAIL] Simulation watchdog expired - design hang ?");
        $finish;
    end

endmodule
