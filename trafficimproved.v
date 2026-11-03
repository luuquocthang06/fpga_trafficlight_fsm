module sensor_filter #(parameter FILTER_CYCLES = 600000) (   // 50 ms @ 12 MHz
    input      clk,
    input      reset,     // active-high
    input      in,
    output reg out
);
    reg s1, s2;
    reg [31:0] cnt;
    always @(posedge clk) begin
        s1 <= in; s2 <= s1;
        if (reset) begin out <= 1'b0; cnt <= 0; end
        else if (s2 == out) cnt <= 0;
        else begin
            cnt <= cnt + 1;
            if (cnt >= FILTER_CYCLES - 1) begin out <= s2; cnt <= 0; end
        end
    end
endmodule


module traffic_ctrl #(
    parameter CLK_HZ     = 12_000_000,
    parameter MIN_GREEN  = 5,    // giay, xanh toi thieu
    parameter MAX_GREEN  = 20,   // giay, xanh toi da khi huong kia dang cho
    parameter GAP_SEC    = 3,    // giay vang xe thi cat xanh (gap-out)
    parameter YELLOW_SEC = 3,
    parameter ALLRED_SEC = 2,
    parameter FLASH_SEC  = 4     // nhay do toi thieu luc khoi dong
) (
    input            clk,
    input            reset,      // active-high
    input            TA,         // co xe huong A (da loc)
    input            TB,         // co xe huong B (da loc)
    input            fault,      // 1 = che do loi: nhay do
    output reg [1:0] LA,
    output reg [1:0] LB,
    output reg [2:0] state
);
    localparam GREEN = 2'b00, YELLOW = 2'b01, RED = 2'b10, OFF = 2'b11;

    localparam F  = 3'd0,   // nhay do (khoi dong / loi)
               S0 = 3'd1,   // A xanh,  B do
               S1 = 3'd2,   // A vang,  B do
               S2 = 3'd3,   // do - do (A -> B)
               S3 = 3'd4,   // A do,    B xanh
               S4 = 3'd5,   // A do,    B vang
               S5 = 3'd6;   // do - do (B -> A)

    reg [31:0] pre;          // chia xung -> 1 giay
    reg [7:0]  secs;         // giay da troi qua trong trang thai
    reg [7:0]  gap;          // giay ke tu lan cuoi cam bien huong dang xanh co xe
    reg        callA, callB; // yeu cau cua huong dang do (chot lai)

    wire greenA   = (state == S0);
    wire greenB   = (state == S3);
    wire Tcur     = greenA ? TA : TB;
    wire sec_tick = (pre == CLK_HZ - 1);

    // ----- trang thai ke tiep (to hop) -----
    reg [2:0] nextstate;
    always @(*) begin
        nextstate = state;
        if (fault && state != F) nextstate = F;
        else case (state)
            F:  if (!fault && secs >= FLASH_SEC) nextstate = S5;
            S0: if (secs >= MIN_GREEN && callB && (gap >= GAP_SEC || secs >= MAX_GREEN)) nextstate = S1;
            S1: if (secs >= YELLOW_SEC) nextstate = S2;
            S2: if (secs >= ALLRED_SEC) nextstate = S3;
            S3: if (secs >= MIN_GREEN && callA && (gap >= GAP_SEC || secs >= MAX_GREEN)) nextstate = S4;
            S4: if (secs >= YELLOW_SEC) nextstate = S5;
            S5: if (secs >= ALLRED_SEC) nextstate = S0;
            default: nextstate = F;
        endcase
    end
    wire advance = (nextstate != state);
    wire blink_n = advance ? 1'b0 : secs[0];

    // ----- ngo ra theo trang thai ke tiep, di qua thanh ghi -----
    function [1:0] light_a(input [2:0] s, input blink);
        case (s)
            S0:      light_a = GREEN;
            S1:      light_a = YELLOW;
            F:       light_a = blink ? OFF : RED;
            default: light_a = RED;
        endcase
    endfunction
    function [1:0] light_b(input [2:0] s, input blink);
        case (s)
            S3:      light_b = GREEN;
            S4:      light_b = YELLOW;
            F:       light_b = blink ? OFF : RED;
            default: light_b = RED;
        endcase
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            state <= F; LA <= RED; LB <= RED;
            pre <= 0; secs <= 0; gap <= 0; callA <= 0; callB <= 0;
        end else begin
            state <= nextstate;
            LA    <= light_a(nextstate, blink_n);
            LB    <= light_b(nextstate, blink_n);

            // bo dem thoi gian
            if (advance) begin pre <= 0; secs <= 0; gap <= 0; end
            else begin
                if (sec_tick) begin
                    pre <= 0;
                    if (secs != 8'hFF) secs <= secs + 1'b1;
                    if ((greenA || greenB) && !Tcur && gap != 8'hFF) gap <= gap + 1'b1;
                end else pre <= pre + 1'b1;
                if ((greenA || greenB) && Tcur) gap <= 0;   // con xe: khoang ho ve 0
            end

            // chot yeu cau: xoa khi huong do duoc xanh
            if (state == S0)  callA <= 1'b0; else if (TA) callA <= 1'b1;
            if (state == S3)  callB <= 1'b0; else if (TB) callB <= 1'b1;
        end
    end
endmodule

// ---------- top cho kit STEP-MAX10 ----------
//   SW1 = TA, SW2 = TB, SW3 = che do loi (nhay do), ON = 1;  KEY4 = reset
//   RGB LED1 = den A, RGB LED2 = den B
//   LED1..LED7 = trang thai F,S0..S5 (one-hot), LED8 = dang loi
module traffic_top #(
    parameter CLK_HZ     = 12_000_000,
    parameter FILTER_MS  = 50,
    parameter MIN_GREEN  = 5,
    parameter MAX_GREEN  = 20,
    parameter GAP_SEC    = 3,
    parameter YELLOW_SEC = 3,
    parameter ALLRED_SEC = 2,
    parameter FLASH_SEC  = 4,
    parameter POR_WIDTH  = 16
) (
    input        clk,
    input        key4_n,        // KEY4, active-low
    input  [2:0] sw,            // SW1, SW2, SW3
    output [2:0] rgb1_n,        // {B,G,R} active-low (chung anode)
    output [2:0] rgb2_n,
    output [7:0] led_n
);
    // reset: power-on + KEY4, nha dong bo
    reg [POR_WIDTH-1:0] por = 0;
    wire por_done = &por;
    always @(posedge clk) if (!por_done) por <= por + 1'b1;
    wire rst_req_n = por_done & key4_n;
    reg [1:0] rs = 2'b00;
    always @(posedge clk or negedge rst_req_n)
        if (!rst_req_n) rs <= 2'b00; else rs <= {rs[0], 1'b1};
    wire reset = ~rs[1];

    localparam FC_RAW = (CLK_HZ / 1000) * FILTER_MS;
    localparam FC     = (FC_RAW < 1) ? 1 : FC_RAW;

    wire TA, TB;
    sensor_filter #(.FILTER_CYCLES(FC)) u_fa (.clk(clk), .reset(reset), .in(sw[0]), .out(TA));
    sensor_filter #(.FILTER_CYCLES(FC)) u_fb (.clk(clk), .reset(reset), .in(sw[1]), .out(TB));
    reg f1 = 0, fault = 0;
    always @(posedge clk) begin f1 <= sw[2]; fault <= f1; end

    wire [1:0] LA, LB;
    wire [2:0] state;
    traffic_ctrl #(.CLK_HZ(CLK_HZ), .MIN_GREEN(MIN_GREEN), .MAX_GREEN(MAX_GREEN),
                   .GAP_SEC(GAP_SEC), .YELLOW_SEC(YELLOW_SEC), .ALLRED_SEC(ALLRED_SEC),
                   .FLASH_SEC(FLASH_SEC)) u_ctrl (
        .clk(clk), .reset(reset), .TA(TA), .TB(TB), .fault(fault),
        .LA(LA), .LB(LB), .state(state));

    function [2:0] rgb_on(input [1:0] c);   // {B,G,R}, 1 = sang
        case (c)
            2'b00:   rgb_on = 3'b010;   // xanh
            2'b01:   rgb_on = 3'b011;   // vang = do + xanh la
            2'b10:   rgb_on = 3'b001;   // do
            default: rgb_on = 3'b000;   // tat
        endcase
    endfunction
    assign rgb1_n = ~rgb_on(LA);
    assign rgb2_n = ~rgb_on(LB);
    assign led_n  = ~{fault, 7'b0000001 << state};
endmodule