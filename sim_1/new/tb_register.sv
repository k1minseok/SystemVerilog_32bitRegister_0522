`timescale 1ns / 1ps

interface reg_interface;
    logic clk;
    logic reset;
    logic [31:0] D;

    logic [31:0] Q;
endinterface


class transaction;
    rand logic [31:0] data;
    logic      [31:0] out;

    task display(string name);
        $display("[%s] data: %x, out: %x", name, data, out);
    endtask
endclass


class generator;
    transaction trans;
    mailbox #(transaction) gen2drv_mbox;
    event gen_next_event;

    // 생성자에 mailbox, event 초기화 추가
    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_event);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.gen_next_event = gen_next_event;
    endfunction

    task run(int count);  // 매개변수로 몇번 반복할지
        repeat (count) begin
            trans = new();  // transaction 인스턴스화를 run task 안에서 진행
            // Garbage collection이 동작해서 메모리에 trasaction class instance Data가 자동으로 정리된다.

            assert (trans.randomize())
            else $error("[GEN] trans.randomize() error!");

            gen2drv_mbox.put(trans);
            trans.display("GEN");
            @(gen_next_event);
        end
    endtask
endclass


class driver;
    transaction trans;
    mailbox #(transaction) gen2drv_mbox;
    event drv_next_event;

    virtual reg_interface reg_intf;

    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual reg_interface reg_intf, event drv_next_event);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.reg_intf       = reg_intf;
        this.drv_next_event = drv_next_event;
    endfunction

    task reset();
        reg_intf.D     <= 0;
        reg_intf.reset <= 1'b1;
        repeat (5) @(posedge reg_intf.clk);
        reg_intf.reset <= 1'b0;
    endtask

    task run();
        forever begin
            // @(posedge reg_intf.clk);
            gen2drv_mbox.get(trans);
            reg_intf.D <= trans.data;  // input

            trans.display("DRV");
            @(posedge reg_intf.clk);  // 여기 지나면 출력
            // driver와 monitor 입, 출력 동기화

            -> drv_next_event;  // event를 이용한 입출력 동기화
        end
    endtask
endclass


class monitor;
    transaction trans;
    mailbox #(transaction) mon2scb_mbox;
    event drv_next_event;

    virtual reg_interface reg_intf;

    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual reg_interface reg_intf, event drv_next_event);
        this.mon2scb_mbox   = mon2scb_mbox;
        this.reg_intf       = reg_intf;
        this.drv_next_event = drv_next_event;
    endfunction

    task run();
        forever begin
            @(drv_next_event);

            trans = new();

            // @(posedge reg_intf.clk);
            trans.data = reg_intf.D;

            @(posedge reg_intf.clk);
            trans.out  = reg_intf.Q;

            mon2scb_mbox.put(trans);
            trans.display("MON");
        end
    endtask
endclass


class scoreboard;
    transaction trans;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_event;

    int total_cnt, pass_cnt, fail_cnt;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_event);
        this.mon2scb_mbox   = mon2scb_mbox;
        this.gen_next_event = gen_next_event;
        total_cnt           = 0;
        pass_cnt            = 0;
        fail_cnt            = 0;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(trans);
            trans.display("SCB");

            if (trans.data == trans.out) begin
                $display(" ---> PASS! %x == %x", trans.data, trans.out);
                pass_cnt++;
            end else begin
                $display(" ---> FAIL! %x != %x", trans.data, trans.out);
                fail_cnt++;
            end
            total_cnt++;

            ->gen_next_event;
        end
    endtask
endclass


class environment;  // OOP AP_main같은 느낌...(각 class 인스턴스화, 초기화, task 실행)
    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;

    event gen_next_event;
    event drv_next_event;

    function new(virtual reg_interface reg_intf);
        gen2drv_mbox = new();
        mon2scb_mbox = new();

        gen = new(gen2drv_mbox, gen_next_event);
        drv = new(gen2drv_mbox, reg_intf, drv_next_event);
        mon = new(mon2scb_mbox, reg_intf, drv_next_event);
        scb = new(mon2scb_mbox, gen_next_event);
    endfunction


    task report();
        $display("=============================");
        $display("==       Final Report      ==");
        $display("=============================");
        $display("Total Test : %d", scb.total_cnt);
        $display("Pass Count : %d", scb.pass_cnt);
        $display("Fail Count : %d", scb.fail_cnt);
        $display("=============================");
        $display("== test bench is finished! ==");
        $display("=============================");
    endtask


    task pre_run();
        drv.reset();
    endtask

    task run();
        fork
            gen.run(20);
            drv.run();
            mon.run();
            scb.run();
        join_any

        report();
        #10 $finish;
    endtask

    task run_test();
        pre_run();
        run();
    endtask
endclass


module tb_register ();
    environment env;
    reg_interface reg_intf ();  // interface instantiation

    register dut (
        .clk(reg_intf.clk),
        .reset(reg_intf.reset),
        .D(reg_intf.D),

        .Q(reg_intf.Q)
    );

    always #5 reg_intf.clk = ~reg_intf.clk;

    initial begin
        reg_intf.clk = 0;
    end

    initial begin
        env = new(reg_intf);
        env.run_test();
    end

endmodule