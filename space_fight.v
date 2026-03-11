// ============================================================
//  8-Bit Space Fighter — DE2-115 (Cyclone IV E)
//  Resolution : 640 x 480 @ 60 Hz  |  System clk : 50 MHz
//  Controls:
//    KEY3 = Move Left  KEY2 = Move Right
//    KEY1 = Shoot      KEY0 = Reset
// ============================================================
module space_fight (
    input  wire        CLOCK_50,
    input  wire        KEY0,
    input  wire        KEY1,
    input  wire        KEY2,
    input  wire        KEY3,
    output wire        VGA_CLK,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B
);

// ============================================================
// 1. Pixel Clock 25 MHz
// ============================================================
reg pix_clk_en;
always @(posedge CLOCK_50 or negedge KEY0)
    if (!KEY0) pix_clk_en <= 1'b0;
    else       pix_clk_en <= ~pix_clk_en;
assign VGA_CLK    = ~pix_clk_en;
assign VGA_SYNC_N = 1'b0;

// ============================================================
// 2. VGA Timing
// ============================================================
localparam H_VISIBLE=640,H_FRONT=16,H_SYNC=96,H_BACK=48,H_TOTAL=800;
localparam V_VISIBLE=480,V_FRONT=10,V_SYNC=2, V_BACK=33,V_TOTAL=525;

reg [9:0] h_cnt, v_cnt;
always @(posedge CLOCK_50 or negedge KEY0) begin
    if (!KEY0) begin h_cnt<=0; v_cnt<=0; end
    else if (pix_clk_en) begin
        if (h_cnt==H_TOTAL-1) begin
            h_cnt<=0;
            v_cnt<=(v_cnt==V_TOTAL-1)?10'd0:v_cnt+10'd1;
        end else h_cnt<=h_cnt+10'd1;
    end
end
assign VGA_HS      = ~((h_cnt>=H_VISIBLE+H_FRONT)&&(h_cnt<H_VISIBLE+H_FRONT+H_SYNC));
assign VGA_VS      = ~((v_cnt>=V_VISIBLE+V_FRONT)&&(v_cnt<V_VISIBLE+V_FRONT+V_SYNC));
wire   visible     =  (h_cnt<H_VISIBLE)&&(v_cnt<V_VISIBLE);
assign VGA_BLANK_N =   visible;

// ============================================================
// 3. Frame Tick ~60 Hz
// ============================================================
reg [19:0] gcnt;
reg        frame_tick;
always @(posedge CLOCK_50 or negedge KEY0) begin
    if (!KEY0) begin gcnt<=0; frame_tick<=0; end
    else begin
        if (gcnt==20'd833332) begin gcnt<=0; frame_tick<=1; end
        else begin gcnt<=gcnt+20'd1; frame_tick<=0; end
    end
end

// ============================================================
// 4. Button Debounce  +  Shoot Latch
//
// k1pulse is exactly 1 clock wide (~20 ns at 50 MHz).
// frame_tick fires once every ~16 ms — the pulse is almost
// always gone before frame_tick arrives.
//
// Fix: k1latch is SET the instant the debounced falling edge
// appears on KEY1, and CLEARED only when the game-logic block
// actually consumes it (on the next frame_tick).
// ============================================================
reg [19:0] db1,db2,db3;
reg k1s,k2s,k3s,k1p,k2p,k3p;
reg k1latch;
always @(posedge CLOCK_50 or negedge KEY0) begin
    if (!KEY0) begin
        db1<=0; db2<=0; db3<=0;
        k1s<=1; k2s<=1; k3s<=1;
        k1p<=1; k2p<=1; k3p<=1;
        k1latch<=0;
    end else begin
        if (KEY1==k1s) db1<=0; else begin db1<=db1+1; if (&db1) k1s<=KEY1; end
        if (KEY2==k2s) db2<=0; else begin db2<=db2+1; if (&db2) k2s<=KEY2; end
        if (KEY3==k3s) db3<=0; else begin db3<=db3+1; if (&db3) k3s<=KEY3; end
        k1p<=k1s; k2p<=k2s; k3p<=k3s;
        // Latch: set on button press, clear when frame_tick consumes it
        if (k1p & ~k1s)      k1latch <= 1;
        else if (frame_tick)  k1latch <= 0;
    end
end

// ============================================================
// 5. Game Constants  (sped up for livelier gameplay)
//   PSPD      player pixels/frame   4 -> 6
//   BSPD      bullet pixels/frame   6 -> 10
//   ESPD      enemy pixels/tick     1 -> 2
//   EDROP     enemy drop pixels    12 -> 14
//   ESLOW_MAX enemy ticks/frame     8 -> 5
// ============================================================
localparam [9:0] SPR_W=16, SPR_H=16, PLY=440, SCW=640;
localparam [9:0] PSPD=6, BSPD=10, ESPD=2, EDROP=14;
localparam [3:0] ESLOW_MAX=4'd5;

// ============================================================
// 6. Game Registers
// ============================================================
reg [9:0] px;
reg       bact; reg [9:0] bx,by;
reg [9:0] e0x,e0y; reg e0v;
reg [9:0] e1x,e1y; reg e1v;
reg [9:0] e2x,e2y; reg e2v;
reg       edir; reg [3:0] eslow;
reg [3:0] score; reg [1:0] lives;
reg       gover, gwin;

// ============================================================
// 7. Sprite ROMs  (called only inside always blocks)
// ============================================================
function [15:0] ship_row;
    input [3:0] r;
    begin
        case(r)
            4'd0:  ship_row=16'b0000000110000000;
            4'd1:  ship_row=16'b0000001111000000;
            4'd2:  ship_row=16'b0000001111000000;
            4'd3:  ship_row=16'b0000011111100000;
            4'd4:  ship_row=16'b0000111111110000;
            4'd5:  ship_row=16'b0001111111111000;
            4'd6:  ship_row=16'b0011111111111100;
            4'd7:  ship_row=16'b0111111111111110;
            4'd8:  ship_row=16'b1111111111111111;
            4'd9:  ship_row=16'b1111111111111111;
            4'd10: ship_row=16'b1110011111100111;
            4'd11: ship_row=16'b1100001111000011;
            4'd12: ship_row=16'b1000000110000001;
            4'd13: ship_row=16'b0000000110000000;
            4'd14: ship_row=16'b0000000110000000;
            default: ship_row=16'd0;
        endcase
    end
endfunction

function [15:0] ghost_row;
    input [3:0] r;
    begin
        case(r)
            4'd0:  ghost_row=16'b0000011111100000;
            4'd1:  ghost_row=16'b0000111111110000;
            4'd2:  ghost_row=16'b0001111111111000;
            4'd3:  ghost_row=16'b0011111111111100;
            4'd4:  ghost_row=16'b0111111111111110;
            4'd5:  ghost_row=16'b0110011001100110;
            4'd6:  ghost_row=16'b0111111111111110;
            4'd7:  ghost_row=16'b0111111111111110;
            4'd8:  ghost_row=16'b0111111111111110;
            4'd9:  ghost_row=16'b0111111111111110;
            4'd10: ghost_row=16'b0110110110110110;
            4'd11: ghost_row=16'b0100100100100100;
            default: ghost_row=16'd0;
        endcase
    end
endfunction

function [7:0] sship_row;
    input [2:0] r;
    begin
        case(r)
            3'd0: sship_row=8'b00011000;
            3'd1: sship_row=8'b00111100;
            3'd2: sship_row=8'b01111110;
            3'd3: sship_row=8'b11111111;
            3'd4: sship_row=8'b11111111;
            3'd5: sship_row=8'b10100101;
            3'd6: sship_row=8'b10000001;
            default: sship_row=8'd0;
        endcase
    end
endfunction

// ============================================================
// 8. Starfield
// ============================================================
function star_on_f;
    input [9:0] hh,vv;
    begin
        star_on_f=
            (hh==23&&vv==17)||(hh==150&&vv==42)||(hh==300&&vv== 8)||
            (hh==512&&vv==30)||(hh==600&&vv==60)||(hh== 80&&vv==90)||
            (hh==200&&vv==110)||(hh==400&&vv==70)||(hh== 55&&vv==140)||
            (hh==620&&vv==120)||(hh==320&&vv==160)||(hh==480&&vv==200)||
            (hh==130&&vv==230)||(hh==560&&vv==180)||(hh==250&&vv==260)||
            (hh==370&&vv==290)||(hh== 40&&vv==310)||(hh==590&&vv==330)||
            (hh==100&&vv==350)||(hh==440&&vv==360)||(hh==220&&vv==390)||
            (hh==500&&vv==270)||(hh==340&&vv==420)||(hh==610&&vv==400)||
            (hh== 70&&vv==410)||(hh==180&&vv==440)||(hh==420&&vv== 50)||
            (hh==270&&vv== 80)||(hh==460&&vv==130)||(hh==160&&vv==310)||
            (hh==530&&vv==240)||(hh== 90&&vv==190);
    end
endfunction

// ============================================================
// 9. Game Logic
// ============================================================
always @(posedge CLOCK_50 or negedge KEY0) begin
    if (!KEY0) begin
        px<=10'd312; bact<=0; bx<=0; by<=0;
        e0x<=10'd100; e0y<=10'd60; e0v<=1;
        e1x<=10'd280; e1y<=10'd60; e1v<=1;
        e2x<=10'd460; e2y<=10'd60; e2v<=1;
        edir<=0; eslow<=0; score<=0; lives<=2'd3;
        gover<=0; gwin<=0;
    end
    else if (frame_tick && !gover && !gwin) begin

        // Player move
        if (!KEY3 && px>10'd0)         px<=px-PSPD;
        if (!KEY2 && px<SCW-SPR_W)     px<=px+PSPD;

        // Shoot — k1latch stays high from button press until this frame clears it
        if (k1latch && !bact) begin
            bact<=1; bx<=px+10'd7; by<=PLY-10'd4;
        end

        // Bullet advance
        if (bact) begin
            if (by<BSPD) bact<=0;
            else         by<=by-BSPD;
        end

        // Enemy slow tick
        eslow<=eslow+4'd1;
        if (eslow==ESLOW_MAX) begin
            eslow<=0;
            if (!edir) begin
                if ((e0v&&e0x>=SCW-SPR_W-ESPD)||(e1v&&e1x>=SCW-SPR_W-ESPD)||(e2v&&e2x>=SCW-SPR_W-ESPD)) begin
                    edir<=1;
                    if(e0v) e0y<=e0y+EDROP;
                    if(e1v) e1y<=e1y+EDROP;
                    if(e2v) e2y<=e2y+EDROP;
                end else begin
                    if(e0v) e0x<=e0x+ESPD;
                    if(e1v) e1x<=e1x+ESPD;
                    if(e2v) e2x<=e2x+ESPD;
                end
            end else begin
                if ((e0v&&e0x<=ESPD)||(e1v&&e1x<=ESPD)||(e2v&&e2x<=ESPD)) begin
                    edir<=0;
                    if(e0v) e0y<=e0y+EDROP;
                    if(e1v) e1y<=e1y+EDROP;
                    if(e2v) e2y<=e2y+EDROP;
                end else begin
                    if(e0v) e0x<=e0x-ESPD;
                    if(e1v) e1x<=e1x-ESPD;
                    if(e2v) e2x<=e2x-ESPD;
                end
            end
        end

        // Bullet-enemy collision
        if (bact) begin
            if (e0v&&bx>=e0x&&bx<=e0x+SPR_W&&by>=e0y&&by<=e0y+SPR_H)
                begin e0v<=0; bact<=0; score<=score+4'd1; end
            if (e1v&&bx>=e1x&&bx<=e1x+SPR_W&&by>=e1y&&by<=e1y+SPR_H)
                begin e1v<=0; bact<=0; score<=score+4'd1; end
            if (e2v&&bx>=e2x&&bx<=e2x+SPR_W&&by>=e2y&&by<=e2y+SPR_H)
                begin e2v<=0; bact<=0; score<=score+4'd1; end
        end

        // Enemy reaches player row
        if ((e0v&&e0y>=PLY-SPR_H)||(e1v&&e1y>=PLY-SPR_H)||(e2v&&e2y>=PLY-SPR_H)) begin
            if (lives>2'd0) begin
                lives<=lives-2'd1;
                e0x<=10'd100; e0y<=10'd60; e0v<=1;
                e1x<=10'd280; e1y<=10'd60; e1v<=1;
                e2x<=10'd460; e2y<=10'd60; e2v<=1;
                edir<=0;
            end else gover<=1;
        end

        // Win condition
        if (!e0v&&!e1v&&!e2v) gwin<=1;
    end
end

// ============================================================
// 10. Pixel Rendering
// RULE: never index directly into a function return value.
//       Capture the return into a reg first, then index.
// ============================================================

// Player
wire [3:0] prx = h_cnt[3:0] - px[3:0];
wire [3:0] pry = v_cnt[3:0] - PLY[3:0];
wire in_ply = (h_cnt>=px)&&(h_cnt<px+SPR_W)&&(v_cnt>=PLY)&&(v_cnt<PLY+SPR_H);
reg [15:0] ship_bits;
reg        ply_on;
always @(*) begin
    ship_bits = ship_row(pry);
    ply_on    = in_ply && ship_bits[4'd15 - prx];
end

// Bullet
wire bul_on = bact&&(h_cnt>=bx)&&(h_cnt<bx+10'd3)&&(v_cnt>=by)&&(v_cnt<by+10'd6);

// Enemy 0
wire [3:0] r0x = h_cnt[3:0] - e0x[3:0];
wire [3:0] r0y = v_cnt[3:0] - e0y[3:0];
wire in_e0 = (e0v)&&(h_cnt>=e0x)&&(h_cnt<e0x+SPR_W)&&(v_cnt>=e0y)&&(v_cnt<e0y+SPR_H);
reg [15:0] ghost_bits0;
reg        e0p;
always @(*) begin
    ghost_bits0 = ghost_row(r0y);
    e0p         = in_e0 && ghost_bits0[4'd15 - r0x];
end

// Enemy 1
wire [3:0] r1x = h_cnt[3:0] - e1x[3:0];
wire [3:0] r1y = v_cnt[3:0] - e1y[3:0];
wire in_e1 = (e1v)&&(h_cnt>=e1x)&&(h_cnt<e1x+SPR_W)&&(v_cnt>=e1y)&&(v_cnt<e1y+SPR_H);
reg [15:0] ghost_bits1;
reg        e1p;
always @(*) begin
    ghost_bits1 = ghost_row(r1y);
    e1p         = in_e1 && ghost_bits1[4'd15 - r1x];
end

// Enemy 2
wire [3:0] r2x = h_cnt[3:0] - e2x[3:0];
wire [3:0] r2y = v_cnt[3:0] - e2y[3:0];
wire in_e2 = (e2v)&&(h_cnt>=e2x)&&(h_cnt<e2x+SPR_W)&&(v_cnt>=e2y)&&(v_cnt<e2y+SPR_H);
reg [15:0] ghost_bits2;
reg        e2p;
always @(*) begin
    ghost_bits2 = ghost_row(r2y);
    e2p         = in_e2 && ghost_bits2[4'd15 - r2x];
end

// Score bar
wire sbar_on = (v_cnt>=10'd466)&&(v_cnt<=10'd473)&&
               (h_cnt>=10'd4)&&(h_cnt<10'd4+{6'd0,score}*10'd12);

// Lives icons
wire inL0 = (lives>=2'd1)&&(h_cnt>=10'd150)&&(h_cnt<10'd158)&&(v_cnt>=10'd465)&&(v_cnt<10'd473);
wire inL1 = (lives>=2'd2)&&(h_cnt>=10'd162)&&(h_cnt<10'd170)&&(v_cnt>=10'd465)&&(v_cnt<10'd473);
wire inL2 = (lives>=2'd3)&&(h_cnt>=10'd174)&&(h_cnt<10'd182)&&(v_cnt>=10'd465)&&(v_cnt<10'd473);
reg [7:0] ss_bits;
reg L0, L1, L2;
always @(*) begin
    ss_bits = sship_row(v_cnt[2:0] - 3'd5);
    L0 = inL0 && ss_bits[3'd7 - (h_cnt[2:0] - 3'd6)];
    L1 = inL1 && ss_bits[3'd7 - (h_cnt[2:0] - 3'd2)];
    L2 = inL2 && ss_bits[3'd7 - (h_cnt[2:0] - 3'd6)];
end
wire liv_on = L0|L1|L2;

// Stars
wire star_on = star_on_f(h_cnt, v_cnt);

// ============================================================
// 11. Text font
// ============================================================
function [7:0] fnt;
    input [3:0] ch; input [2:0] row;
    begin
        case(ch)
            4'd0:case(row) 3'd0:fnt=8'h3E;3'd1:fnt=8'h60;3'd2:fnt=8'h6E;3'd3:fnt=8'h66;3'd4:fnt=8'h3E;3'd5:fnt=8'h06;3'd6:fnt=8'h3E;default:fnt=0;endcase// G
            4'd1:case(row) 3'd0:fnt=8'h38;3'd1:fnt=8'h6C;3'd2:fnt=8'hC6;3'd3:fnt=8'hFE;3'd4:fnt=8'hC6;3'd5:fnt=8'hC6;3'd6:fnt=8'hC6;default:fnt=0;endcase// A
            4'd2:case(row) 3'd0:fnt=8'hC6;3'd1:fnt=8'hEE;3'd2:fnt=8'hFE;3'd3:fnt=8'hD6;3'd4:fnt=8'hC6;3'd5:fnt=8'hC6;3'd6:fnt=8'hC6;default:fnt=0;endcase// M
            4'd3:case(row) 3'd0:fnt=8'hFE;3'd1:fnt=8'hC0;3'd2:fnt=8'hFC;3'd3:fnt=8'hC0;3'd4:fnt=8'hC0;3'd5:fnt=8'hC0;3'd6:fnt=8'hFE;default:fnt=0;endcase// E
            4'd4:case(row) default:fnt=0;endcase// space
            4'd5:case(row) 3'd0:fnt=8'h7C;3'd1:fnt=8'hC6;3'd2:fnt=8'hC6;3'd3:fnt=8'hC6;3'd4:fnt=8'hC6;3'd5:fnt=8'hC6;3'd6:fnt=8'h7C;default:fnt=0;endcase// O
            4'd6:case(row) 3'd0:fnt=8'hC6;3'd1:fnt=8'hC6;3'd2:fnt=8'hC6;3'd3:fnt=8'hC6;3'd4:fnt=8'h6C;3'd5:fnt=8'h38;3'd6:fnt=8'h10;default:fnt=0;endcase// V
            4'd7:case(row) 3'd0:fnt=8'hFE;3'd1:fnt=8'hC0;3'd2:fnt=8'hFC;3'd3:fnt=8'hC0;3'd4:fnt=8'hC0;3'd5:fnt=8'hC0;3'd6:fnt=8'hFE;default:fnt=0;endcase// E
            4'd8:case(row) 3'd0:fnt=8'hFC;3'd1:fnt=8'hC6;3'd2:fnt=8'hFC;3'd3:fnt=8'hC8;3'd4:fnt=8'hC6;3'd5:fnt=8'hC6;3'd6:fnt=8'hC6;default:fnt=0;endcase// R
            default:fnt=0;
        endcase
    end
endfunction

function [7:0] fntw;
    input [2:0] ch; input [2:0] row;
    begin
        case(ch)
            3'd0:case(row) 3'd0:fntw=8'hC6;3'd1:fntw=8'hC6;3'd2:fntw=8'h6C;3'd3:fntw=8'h38;3'd4:fntw=8'h10;3'd5:fntw=8'h10;3'd6:fntw=8'h10;default:fntw=0;endcase// Y
            3'd1:case(row) 3'd0:fntw=8'h7C;3'd1:fntw=8'hC6;3'd2:fntw=8'hC6;3'd3:fntw=8'hC6;3'd4:fntw=8'hC6;3'd5:fntw=8'hC6;3'd6:fntw=8'h7C;default:fntw=0;endcase// O
            3'd2:case(row) 3'd0:fntw=8'hC6;3'd1:fntw=8'hC6;3'd2:fntw=8'hC6;3'd3:fntw=8'hC6;3'd4:fntw=8'hC6;3'd5:fntw=8'hC6;3'd6:fntw=8'h7C;default:fntw=0;endcase// U
            3'd3:case(row) default:fntw=0;endcase// space
            3'd4:case(row) 3'd0:fntw=8'hC6;3'd1:fntw=8'hC6;3'd2:fntw=8'hC6;3'd3:fntw=8'hD6;3'd4:fntw=8'hFE;3'd5:fntw=8'h6C;3'd6:fntw=8'h28;default:fntw=0;endcase// W
            3'd5:case(row) 3'd0:fntw=8'h7C;3'd1:fntw=8'h10;3'd2:fntw=8'h10;3'd3:fntw=8'h10;3'd4:fntw=8'h10;3'd5:fntw=8'h10;3'd6:fntw=8'h7C;default:fntw=0;endcase// I
            3'd6:case(row) 3'd0:fntw=8'hC6;3'd1:fntw=8'hE6;3'd2:fntw=8'hF6;3'd3:fntw=8'hDE;3'd4:fntw=8'hCE;3'd5:fntw=8'hC6;3'd6:fntw=8'hC6;default:fntw=0;endcase// N
            default:fntw=0;
        endcase
    end
endfunction

// ============================================================
// 12. Banners
// ============================================================
wire ban_area = (h_cnt>=10'd200)&&(h_cnt<10'd440)&&(v_cnt>=10'd210)&&(v_cnt<10'd270);
wire go_ban   = gover && ban_area;
wire win_ban  = gwin  && ban_area;

wire in_got = (h_cnt>=10'd284)&&(h_cnt<10'd356)&&(v_cnt>=10'd226)&&(v_cnt<10'd233);
wire [5:0] gorx = h_cnt[5:0] - 6'd28;
wire [2:0] goc  = gorx[5:3];
wire [2:0] gobx = gorx[2:0];
wire [2:0] gory = v_cnt[2:0] - 3'd2;
reg [7:0] go_bits;
reg       got_px;
always @(*) begin
    go_bits = fnt({1'b0,goc}, gory);
    got_px  = gover && in_got && go_bits[3'd7 - gobx];
end

wire in_wt = (h_cnt>=10'd302)&&(h_cnt<10'd358)&&(v_cnt>=10'd226)&&(v_cnt<10'd233);
wire [5:0] wrx = h_cnt[5:0] - 6'd46;
wire [2:0] wc  = wrx[5:3];
wire [2:0] wbx = wrx[2:0];
wire [2:0] wry = v_cnt[2:0] - 3'd2;
reg [7:0] win_bits;
reg       win_px;
always @(*) begin
    win_bits = fntw(wc, wry);
    win_px   = gwin && in_wt && win_bits[3'd7 - wbx];
end

// ============================================================
// 13. Colour Mixer
// ============================================================
reg [7:0] ro, go_out, bo;
always @(*) begin
    if (!visible)           {ro,go_out,bo}=24'h000000;
    else if (go_ban)        {ro,go_out,bo}=got_px?24'hFFFFFF:24'hCC0000;
    else if (win_ban)       {ro,go_out,bo}=win_px?24'hFFFFFF:24'h00AA00;
    else if (bul_on)        {ro,go_out,bo}=24'hFFFF00;
    else if (ply_on)        {ro,go_out,bo}=24'h00FFFF;
    else if (e0p|e1p|e2p)  {ro,go_out,bo}=24'hFFFFFF;
    else if (sbar_on)       {ro,go_out,bo}=24'h00FF00;
    else if (liv_on)        {ro,go_out,bo}=24'hFFFFFF;
    else if (star_on)       {ro,go_out,bo}=24'hAAAAAA;
    else                    {ro,go_out,bo}=24'h000005;
end

assign VGA_R = ro;
assign VGA_G = go_out;
assign VGA_B = bo;

endmodule