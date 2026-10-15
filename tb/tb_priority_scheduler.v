`timescale 1ns / 1ps
//============================================================================
// Testbench   : tb_priority_scheduler
// Description : Standalone unit test for the combinational priority
//               scheduler. It sweeps the available power from 0 kW to
//               15 kW and checks after every step:
//                 U1 : total_granted never exceeds available_power
//                 U2 : the granted set is always a prefix of the priority
//                      list (no lower priority load without higher ones)
//                 U3 : adding more available power never DISCONNECTS a load
//                      (monotonicity / no oscillation)
//                 U4 : known vectors (0 kW, 5 kW exact fit, 10 kW, 15 kW)
//============================================================================
module tb_priority_scheduler;

    reg  [7:0]  available_power;
    reg  [47:0] load_demand;
    wire [5:0]  grant;
    wire [7:0]  total_granted;
    wire [7:0]  total_demand;
    wire        partial_shed;

    priority_scheduler dut (
        .available_power (available_power),
        .load_demand     (load_demand),
        .grant           (grant),
        .total_granted   (total_granted),
        .total_demand    (total_demand),
        .partial_shed    (partial_shed)
    );

    integer errors = 0;
    integer checks = 0;
    integer p;
    reg [5:0] prev_grant;

    // demands : 2,1,1,1,2,3 kW  (total 10 kW)
    initial load_demand = {8'd3, 8'd2, 8'd1, 8'd1, 8'd1, 8'd2};

    // prefix test : grant[k]=1 => grant[k-1]=1
    function is_prefix;
        input [5:0] g;
        begin
            is_prefix = !( (g[1] && !g[0]) || (g[2] && !g[1]) ||
                           (g[3] && !g[2]) || (g[4] && !g[3]) ||
                           (g[5] && !g[4]) );
        end
    endfunction

    initial begin
        //----------- U4 : known vectors -----------------------------
        available_power = 8'd0;  #1;
        checks = checks + 1;
        if (grant !== 6'b000000 || total_granted !== 8'd0) begin
            errors = errors + 1;
            $display("[FAIL] 0 kW : grant=%b granted=%0d", grant, total_granted);
        end else $display("[PASS] 0 kW  -> grant=%b granted=%0d kW", grant, total_granted);

        available_power = 8'd5;  #1;
        checks = checks + 1;
        if (grant !== 6'b001111 || total_granted !== 8'd5) begin
            errors = errors + 1;
            $display("[FAIL] 5 kW : grant=%b granted=%0d", grant, total_granted);
        end else $display("[PASS] 5 kW  -> grant=%b granted=%0d kW (exact fit)", grant, total_granted);

        available_power = 8'd10; #1;
        checks = checks + 1;
        if (grant !== 6'b111111 || total_granted !== 8'd10) begin
            errors = errors + 1;
            $display("[FAIL] 10 kW : grant=%b granted=%0d", grant, total_granted);
        end else $display("[PASS] 10 kW -> grant=%b granted=%0d kW (full demand)", grant, total_granted);

        available_power = 8'd15; #1;
        checks = checks + 1;
        if (total_granted !== 8'd10 || partial_shed !== 1'b0) begin
            errors = errors + 1;
            $display("[FAIL] 15 kW : granted=%0d partial_shed=%b", total_granted, partial_shed);
        end else $display("[PASS] 15 kW -> granted=%0d kW, no shedding", total_granted);

        //----------- U1..U3 : full sweep 0..15 kW ---------------------
        prev_grant = 6'b000000;
        for (p = 0; p <= 15; p = p + 1) begin
            available_power = p; #1;

            checks = checks + 1;
            if (total_granted > available_power) begin
                errors = errors + 1;
                $display("[FAIL] U1 : %0d kW available but %0d kW granted", available_power, total_granted);
            end

            checks = checks + 1;
            if (!is_prefix(grant)) begin
                errors = errors + 1;
                $display("[FAIL] U2 : grant %b is not a priority prefix (avail=%0d)", grant, available_power);
            end

            checks = checks + 1;
            if ((prev_grant & grant) !== prev_grant) begin
                errors = errors + 1;
                $display("[FAIL] U3 : load dropped when power increased (prev=%b now=%b)", prev_grant, grant);
            end

            $display("[INFO] avail=%2d kW -> grant=%b granted=%2d kW shed=%b",
                     available_power, grant, total_granted, partial_shed);
            prev_grant = grant;
        end

        $display("=================================================================");
        $display(" PRIORITY SCHEDULER UNIT TEST : checks=%0d errors=%0d", checks, errors);
        if (errors == 0) $display(" RESULT     : **** ALL TESTS PASSED ****");
        else             $display(" RESULT     : **** %0d TEST(S) FAILED ****", errors);
        $display("=================================================================");
        $finish;
    end

endmodule
