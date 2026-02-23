// -------------------------------------------------------------------------------
// Company:
// Engineer:   Mario Prato
//
// Create Date:    10:07:18 11/22/2012
// Design Name:    divmmc ver. 1.0
// Module Name:    divmmc
// Project Name:   divmmc
// Target Devices: xc9572xl-vq64
// Tool versions:  ise 12.3
// Description:    zx spectrum mmc sd interface
//
// Converted from VHDL to Verilog
//
// versione 1.0
// fitter conf:
// optimize speed
// slew rate slow
// pin termination float
// use global clock
// gnd on unused i/o pin
// macrocell power settings std
// logic optimization speed
// multi level logic optimization
//
// collapsing input limit 54
// collapsing pterm limit 60
// -------------------------------------------------------------------------------

module divmmc (
    // Z80 CPU signals
    input  wire [15:0] A,
    inout  wire [7:0]  D,
    input  wire        iorq,
    input  wire        mreq,
    input  wire        wr,
    input  wire        rd,
    input  wire        m1,
    input  wire        reset,
    input  wire        clock,    // Z80 Clock from ULA chip (must be negated from edge connector signal)

    // RAM/ROM signals
    output wire        romcs,    // 1 -> page out spectrum rom
    output wire        romoe,    // eeprom oe pin
    output wire        romwr,    // eeprom wr pin
    output wire        ramoe,    // ram oe pin
    output wire        ramwr,    // ram wr pin
    output wire [5:0]  bankout,  // ram bank

    // SPI interface
    output reg  [1:0]  card,         // Cards CS (default: 2'b11)
    output reg         spi_clock,    // card clock (default: 1)
    output reg         spi_dataout,  // card data in (default: 1)
    input  wire        spi_datain,   // card data out

    // Various
    input  wire        poweron,      // low pulse on poweron
    input  wire        eprom,        // eprom jumper
    output wire        mapcondout    // hi when divmmc mem paged in
);

    // -------------------------------------------------------------------------
    // Port constants
    // -------------------------------------------------------------------------
    localparam DIVIDE_CONTROL_PORT = 8'hE3; // port %11100011
    localparam ZXMMC_CONTROL_PORT  = 8'hE7;
    localparam ZXMMC_SPI_PORT      = 8'hEB;

    // -------------------------------------------------------------------------
    // Transmission state encoding
    // -------------------------------------------------------------------------
    localparam IDLE     = 2'd0;
    localparam SAMPLE   = 2'd1;
    localparam TRANSMIT = 2'd2;

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    wire [7:0] address = A[7:0];

    reg  [5:0]  bank     = 6'b000000;
    reg         mapterm_r;
    reg         mapcond  = 1'b0;
    reg         conmem   = 1'b0;
    reg         mapram   = 1'b0;
    reg         automap  = 1'b0;

    wire        bank3;
    wire        mapterm;
    wire        map3DXX;
    wire        map1F00;
    wire        divideio;
    wire        zxmmcio;

    reg  [1:0]  transState = IDLE;
    reg  [3:0]  TState     = 4'b0000;
    reg  [7:0]  fromSDByte = 8'hFF;
    reg  [7:0]  toSDByte   = 8'hFF;
    reg  [7:0]  toCPUByte  = 8'hFF;

    // -------------------------------------------------------------------------
    // Combinational decode
    // -------------------------------------------------------------------------
    assign bank3 = (bank == 6'b000011);

    // Automap trigger addresses
    assign mapterm = (A == 16'h0000) | (A == 16'h0008) | (A == 16'h0038) |
                     (A == 16'h0066) | (A == 16'h04C6) | (A == 16'h0562);

    assign map3DXX = (A[15:8] == 8'b00111101);         // 3D00–3DFF
    assign map1F00 = (A[15:3] != 13'b0001111111111);   // 0 for 1FF8–1FFF, 1 otherwise

    // I/O strobes (active-low qualified)
    assign divideio = ~(iorq == 1'b0 && wr == 1'b0 && m1 == 1'b1 &&
                        address == DIVIDE_CONTROL_PORT);

    assign zxmmcio  = ~(address == ZXMMC_CONTROL_PORT && iorq == 1'b0 &&
                        m1 == 1'b1 && wr == 1'b0);

    // -------------------------------------------------------------------------
    // ROM / RAM output-enable and write-enable logic
    // -------------------------------------------------------------------------
    assign romoe = rd | A[15] | A[14] | A[13] |
                   (~conmem &  mapram) |
                   (~conmem & ~automap) |
                   (~conmem &  eprom);

    assign romwr = wr | A[13] | A[14] | A[15] | ~eprom | ~conmem;

    assign ramoe = rd | A[15] | A[14] |
                   (~A[13] & ~mapram) |
                   (~A[13] &  conmem) |
                   (~conmem & ~automap) |
                   (~conmem &  eprom & ~mapram);

    assign ramwr = wr | A[15] | A[14] | ~A[13] |
                   (~conmem &  mapram & bank3) |
                   (~conmem & ~automap) |
                   (~conmem &  eprom & ~mapram);

    assign romcs = (automap & ~eprom) | (automap & mapram) | conmem;

    // -------------------------------------------------------------------------
    // RAM bank output
    // -------------------------------------------------------------------------
    assign bankout[0] = bank[0] |  ~A[13];
    assign bankout[1] = bank[1] |  ~A[13];
    assign bankout[2] = bank[2] &   A[13];
    assign bankout[3] = bank[3] &   A[13];
    assign bankout[4] = bank[4] &   A[13];
    assign bankout[5] = bank[5] &   A[13];

    // -------------------------------------------------------------------------
    // Automap logic — triggered on falling edge of MREQ
    // -------------------------------------------------------------------------
    always @(negedge mreq) begin
        if (m1 == 1'b0) begin
            mapcond <= mapterm | map3DXX | (mapcond & map1F00);
            automap <= mapcond | map3DXX;   // uses old mapcond (non-blocking)
        end
    end

    assign mapcondout = mapcond;

    // -------------------------------------------------------------------------
    // DivIDE control port — bank / mapram / conmem register
    // Async reset on poweron low; latches on rising edge of divideio strobe
    // -------------------------------------------------------------------------
    always @(negedge poweron or posedge divideio) begin
        if (poweron == 1'b0) begin
            bank   <= 6'b000000;
            mapram <= 1'b0;
            conmem <= 1'b0;
        end else begin
            bank[5:0] <= D[5:0];
            mapram    <= D[6] | mapram;   // once set, mapram is sticky
            conmem    <= D[7];
        end
    end

    // -------------------------------------------------------------------------
    // Card chip-select register (ZXMMC control port 0xE7)
    // -------------------------------------------------------------------------
    always @(negedge reset or posedge zxmmcio) begin
        if (reset == 1'b0) begin
            card[0] <= 1'b1;
            card[1] <= 1'b1;
        end else begin
            card[0] <= D[0];
            card[1] <= D[1];
        end
    end

    // -------------------------------------------------------------------------
    // SPI byte transmission / reception state machine
    // Clocked on falling edge of Z80 clock; async reset on reset low
    // -------------------------------------------------------------------------
    always @(negedge reset or negedge clock) begin
        if (reset == 1'b0) begin
            transState  <= IDLE;
            TState      <= 4'b0000;
            fromSDByte  <= 8'hFF;
            toSDByte    <= 8'hFF;
            toCPUByte   <= 8'hFF;
            spi_clock   <= 1'b0;   // TState[0] after reset = 0
            spi_dataout <= 1'b1;   // toSDByte[7] after reset = 1
        end else begin
            // --- State machine ---
            case (transState)

                IDLE: begin
                    // Wait for an I/O request on the SPI port
                    if (address == ZXMMC_SPI_PORT && iorq == 1'b0 && m1 == 1'b1)
                        transState <= SAMPLE;
                end

                SAMPLE: begin
                    // Latch outgoing byte if this is a write
                    if (wr == 1'b0)
                        toSDByte <= D;
                    transState <= TRANSMIT;
                end

                TRANSMIT: begin
                    TState <= TState + 1'b1;

                    if (TState < 4'd15) begin
                        // Shift on odd T-states (old TState value)
                        if (TState[0] == 1'b1) begin
                            toSDByte   <= {toSDByte[6:0],   1'b1};
                            fromSDByte <= {fromSDByte[6:0], spi_datain};
                        end
                    end else begin
                        if (TState == 4'd15) begin
                            // Capture the final received bit
                            toCPUByte <= {fromSDByte[6:0], spi_datain};
                            // Chain directly into next byte or return to IDLE
                            if (address == ZXMMC_SPI_PORT && iorq == 1'b0 &&
                                m1 == 1'b1 && wr == 1'b0) begin
                                toSDByte   <= D;
                                transState <= TRANSMIT;
                            end else begin
                                transState <= IDLE;
                            end
                        end
                    end
                end

                default: ;

            endcase

            // SPI pin outputs — reflect state after each clock edge
            spi_clock   <= TState[0];    // uses old TState (non-blocking)
            spi_dataout <= toSDByte[7];  // uses old toSDByte (non-blocking)
        end
    end

    // -------------------------------------------------------------------------
    // Data bus tri-state driver — drive toCPUByte on SPI port reads
    // -------------------------------------------------------------------------
    assign D = ((address == ZXMMC_SPI_PORT) && (iorq == 1'b0) &&
                (rd == 1'b0) && (m1 == 1'b1)) ? toCPUByte : 8'bz;

endmodule
