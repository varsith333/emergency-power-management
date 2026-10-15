`timescale 1ns / 1ps
//
// epms_top - Digital Emergency Power Management System
//
// Six loads, always connected, the user can't switch any of them off. When
// whatever source we're on can't cover the demand the controller sheds the
// least important loads, and puts them back in priority order as soon as
// there's room again.
//
//   L1  medical / life support    2 kW   highest priority
//   L2  control & communication   1 kW
//   L3  emergency lighting        1 kW
//   L4  security system           1 kW
//   L5  water pump                2 kW
//   L6  HVAC / vent fan           3 kW   lowest priority
//                                 ----
//   total                         10 kW
//
//   mains  12 kW -> everything runs
//   gen    10 kW -> everything runs
//   batt  <= 8 kW -> shedding starts
//
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
    // load demands, kW
    parameter DEMAND_L1         = 8'd2,   // medical
    parameter DEMAND_L2         = 8'd1,   // control & comms
    parameter DEMAND_L3         = 8'd1,   // emergency lighting
    parameter DEMAND_L4         = 8'd1,   // security
    parameter DEMAND_L5         = 8'd2,   // water pump
    parameter DEMAND_L6         = 8'd3    // HVAC
) (
    input  wire       clk,
    input  wire       rst_n,
    // power environment
    input  wire       mains_ok,
    input  wire       gen_ready,
    input  wire       battery_low,
    input  wire [7:0] battery_capacity,
    // contactor drives
    output wire [5:0] load_on,
    output wire       gen_request,
    // monitoring / status
    output wire [1:0] source_sel,
    output wire [7:0] available_power,
    output wire [7:0] total_connected,
    output wire       partial_shed,
    output wire       emergency,
    output wire       energising,
    output wire [2:0] state_out,
    // alarms
    output wire       buzzer,
    output wire       led_mains,
    output wire       led_battery,
    output wire       led_gen,
    output wire       led_blackout,
    output wire       led_low_batt,
    output wire       led_overload,
    // displays
    output wire [6:0] seg_mode,   // source code 0=MAINS 1=BATT 2=GEN 3=BLACK
    output wire [6:0] seg_tens,   // connected load, tens of kW
    output wire [6:0] seg_ones
);

    localparam [47:0] LOAD_DEMAND = {DEMAND_L6, DEMAND_L5, DEMAND_L4,
                                     DEMAND_L3, DEMAND_L2, DEMAND_L1};

    wire [5:0] grant;
    wire [7:0] total_granted;
    wire [7:0] total_demand;

    // which source are we on and how much does it give us
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

    // who gets it - combinational
    priority_scheduler u_sched (
        .available_power (available_power),
        .load_demand     (LOAD_DEMAND),
        .grant           (grant),
        .total_granted   (total_granted),
        .total_demand    (total_demand),
        .partial_shed    (partial_shed)
    );

    // and actually switching them, fast off / slow back on
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

    // which source we're on
    seven_seg u_seg_mode (
        .on    (1'b1),
        .value ({2'b00, source_sel}),
        .seg   (seg_mode)
    );

    // how many kW are actually connected, split into two decimal digits
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
