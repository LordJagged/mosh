use std::{
    collections::HashMap,
    ptr::{null, null_mut},
};

mod vm_helpers;

use crate::{
    compiler,
    equal::Equal,
    fasl::Fasl,
    gc::{Gc, GcRef},
    objects::{Closure, Object, Pair, Symbol, Vox},
    op::Op,
    procs::{self, default_free_vars},
    psyntax,
    read::ReadError,
};

const STACK_SIZE: usize = 1024;
const MAX_NUM_VALUES: usize = 256;

#[macro_export]
macro_rules! branch_number_cmp_op {
    ($op:tt, $self:ident) => {
        {
            let skip_offset = $self.isize_operand();
            match ($self.pop(), $self.ac) {
                (Object::Number(lhs), Object::Number(rhs)) => {
                    let op_result = lhs $op rhs;
                    $self.set_return_value(Object::make_bool(op_result));
                    if op_result {
                        // go to then.
                    } else {
                        // Branch and jump to else.
                        $self.pc = $self.jump($self.pc, skip_offset - 1);
                    }
                }
                obj => {
                    panic!("{}: numbers requierd but got {:?}",  stringify!($op), obj);
                }
            }
        }
    };
}

#[macro_export]
macro_rules! number_cmp_op {
    ($op:tt, $self:ident) => {
        {
            match ($self.pop(), $self.ac) {
                (Object::Number(l), Object::Number(r)) => {
                    $self.set_return_value(Object::make_bool(l $op r))
                }
                obj => {
                    panic!("{}: numbers required but got {:?}",  stringify!($op), obj);
                }
            }
        }
    };
}

struct Registers {
    pub ac: Object,
    pub dc: Object,
    pub pc: *const Object,
    pub sp_offset: isize,
    pub fp_offset: isize,
}

impl Registers {
    fn new() -> Self {
        Self {
            ac: Object::Unspecified,
            dc: Object::Unspecified,
            pc: null(),
            sp_offset: 0,
            fp_offset: 0,
        }
    }
}

pub struct Vm {
    pub gc: Box<Gc>,
    // Program counter
    pc: *const Object,
    // The stack.
    stack: [Object; STACK_SIZE],
    // accumulator register.
    pub ac: Object,
    // display closure register.
    dc: Object,
    // expected register to retain expected value for tests.
    pub expected: Object,
    // stack pointer.
    sp: *mut Object,
    // frame pointer.
    fp: *mut Object,
    // global variables.
    globals: HashMap<GcRef<Symbol>, Object>,
    // We keep references to operators in base libraries so that the lib_ops live longer than every call of run.
    // If we kept operators as local variable, it can/will be immediately freed after run(lib_ops).
    lib_compiler: Vec<Object>,
    lib_psyntax: Vec<Object>,
    pub dynamic_winders: Object,
    // Return values.
    values: [Object; MAX_NUM_VALUES],
    num_values: usize,
    is_initialized: bool,
    pub rtds: HashMap<Object, Object>,
    pub should_load_compiler: bool,
    pub compiled_programs: Vec<Object>,
    pub trigger0_code: Vec<Object>,
    pub eval_code: Vec<Object>,
    pub ret_code: Vec<Object>,
    pub call_by_name_code: Vec<Object>,
    pub closure_for_evaluate: Object,
    current_input_port: Object,
    saved_registers: Registers,
    // Note when we add new vars here, please make sure we take care of them in mark_roots.
    // Otherwise they can cause memory leak or double free.
}

impl Vm {
    pub fn new() -> Self {
        let mut ret = Self {
            gc: Box::new(Gc::new()),
            stack: [Object::Unspecified; STACK_SIZE],
            ac: Object::Unspecified,
            dc: Object::Unspecified,
            expected: Object::Unspecified,
            pc: null_mut(),
            sp: null_mut(),
            fp: null_mut(),
            globals: HashMap::new(),
            lib_compiler: vec![],
            lib_psyntax: vec![],
            dynamic_winders: Object::Unspecified,
            num_values: 0,
            values: [Object::Unspecified; MAX_NUM_VALUES],
            rtds: HashMap::new(),
            should_load_compiler: false,
            is_initialized: false,
            compiled_programs: vec![],
            trigger0_code: vec![],
            eval_code: vec![],
            ret_code: vec![],
            call_by_name_code: vec![],
            closure_for_evaluate: Object::Unspecified,
            current_input_port: Object::Unspecified,
            saved_registers: Registers::new(),
        };
        ret.trigger0_code.push(Object::Instruction(Op::Constant));
        ret.trigger0_code.push(Object::Unspecified);
        ret.trigger0_code.push(Object::Instruction(Op::Call));
        ret.trigger0_code.push(Object::Number(0));
        ret.trigger0_code.push(Object::Instruction(Op::Return));
        ret.trigger0_code.push(Object::Number(0));
        ret.trigger0_code.push(Object::Instruction(Op::Halt));

        ret.call_by_name_code.push(Object::Instruction(Op::Frame));
        ret.call_by_name_code.push(Object::Number(8));
        ret.call_by_name_code
            .push(Object::Instruction(Op::Constant));
        ret.call_by_name_code.push(Object::Unspecified);
        ret.call_by_name_code.push(Object::Instruction(Op::Push));
        ret.call_by_name_code
            .push(Object::Instruction(Op::ReferGlobal));
        ret.call_by_name_code.push(Object::Unspecified);
        ret.call_by_name_code.push(Object::Instruction(Op::Call));
        ret.call_by_name_code.push(Object::Number(1));
        ret.call_by_name_code.push(Object::Instruction(Op::Halt));

        ret
    }

    pub fn intern(&mut self, s: &str) -> GcRef<Symbol> {
        self.gc.intern(s)
    }

    pub fn values(&mut self, values: &[Object]) -> Object {
        let n = values.len();
        self.num_values = n;
        if 0 == n {
            return Object::Unspecified;
        }
        for i in 1..n as usize {
            if i >= MAX_NUM_VALUES {
                panic!("values: too many values");
            }
            self.values[i - 1] = values[i];
        }
        // this is set to ac later.
        return values[0];
    }

    fn initialize_free_vars(&mut self, ops: *const Object, ops_len: usize) {
        let free_vars = default_free_vars(&mut self.gc);
        let mut display = self.gc.alloc(Closure::new(
            ops,
            ops_len,
            0,
            false,
            free_vars,
            Object::False,
        ));

        display.prev = self.dc;
        let free_vars = default_free_vars(&mut self.gc);
        self.closure_for_evaluate = Object::Closure(self.gc.alloc(Closure::new(
            null(),
            0,
            0,
            false,
            free_vars,
            Object::False,
        )));
        self.dc = Object::Closure(display);
    }

    pub fn mark_and_sweep(&mut self) {
        if self.gc.should_gc() {
            #[cfg(feature = "debug_log_gc")]
            println!("-- gc begin");

            self.mark_roots();
            self.gc.collect_garbage();

            #[cfg(feature = "debug_log_gc")]
            println!("-- gc end");
        }
    }

    fn mark_roots(&mut self) {
        // Ports.
        self.gc.mark_object(self.current_input_port);

        for &compiled in &self.compiled_programs {
            self.gc.mark_object(compiled);
        }

        for &obj in &self.trigger0_code {
            self.gc.mark_object(obj);
        }

        for &obj in &self.eval_code {
            self.gc.mark_object(obj);
        }

        for &obj in &self.ret_code {
            self.gc.mark_object(obj);
        }

        for &obj in &self.call_by_name_code {
            self.gc.mark_object(obj);
        }

        self.gc.mark_object(self.saved_registers.ac);
        self.gc.mark_object(self.saved_registers.dc);

        self.gc.mark_object(self.closure_for_evaluate);

        // Base library ops.
        for op in &self.lib_compiler {
            self.gc.mark_object(*op);
        }
        for op in &self.lib_psyntax {
            self.gc.mark_object(*op);
        }

        self.gc.mark_object(self.dynamic_winders);

        // Stack.
        for &obj in &self.stack[0..self.stack_len()] {
            self.gc.mark_object(obj);
        }

        // Values.
        for &obj in &self.values[0..self.num_values] {
            self.gc.mark_object(obj);
        }

        // Symbols.
        let symbols = self
            .gc
            .symbols
            .values()
            .cloned()
            .collect::<Vec<GcRef<Symbol>>>();
        for symbol in symbols {
            self.gc.mark_object(Object::Symbol(symbol));
        }

        // Global variables.
        for &obj in self.globals.values() {
            self.gc.mark_object(obj);
        }

        // RTDs.
        for (k, v) in self.rtds.iter() {
            self.gc.mark_object(*k);
            self.gc.mark_object(*v);
        }

        // Registers.
        self.gc.mark_object(self.ac);
        self.gc.mark_object(self.dc);
        self.gc.mark_object(self.expected);
    }

    pub fn run(&mut self, ops: *const Object, ops_len: usize) -> Object {
        if !self.is_initialized {
            // Create display closure and make free variables accessible.
            self.initialize_free_vars(ops, ops_len);

            // Load the base library.
            self.load_compiler();
            self.is_initialized = true;
        }
        // Run the program.
        let ret = self.run_ops(ops);

        // Clean up so that GC can sweep them.
        self.reset_roots();
        ret
    }

    fn load_compiler(&mut self) -> Object {
        let mut fasl = Fasl {
            bytes: compiler::U8_ARRAY,
        };
        self.lib_compiler = if self.should_load_compiler {
            fasl.read_all_sexp(&mut self.gc)
        } else {
            vec![Object::Instruction(Op::Halt)]
        };
        self.run_ops(self.lib_compiler.as_ptr())
    }

    pub fn enable_r7rs(&mut self, args: Object) -> Object {
        let mut fasl = Fasl {
            bytes: psyntax::U8_ARRAY,
        };
        self.lib_psyntax = if self.should_load_compiler {
            // Global variables.
            let sym = self.gc.symbol_intern("%verbose");
            self.set_global_value(sym.to_symbol(), Object::True);

            let sym = self.gc.symbol_intern("%clean-acc");
            self.set_global_value(sym.to_symbol(), Object::False);

            let sym = self.gc.symbol_intern("%disable-acc");
            self.set_global_value(sym.to_symbol(), Object::True);

            let sym = self.gc.symbol_intern("*command-line-args*");
            let args = args;
            self.set_global_value(sym.to_symbol(), args);

            let sym = self.gc.symbol_intern("%loadpath");
            let path = self.gc.new_string(".");
            self.set_global_value(sym.to_symbol(), path);

            let sym = self.gc.symbol_intern("%vm-import-spec");
            self.set_global_value(sym.to_symbol(), Object::False);
            fasl.read_all_sexp(&mut self.gc)
        } else {
            vec![Object::Instruction(Op::Halt)]
        };

        self.run(self.lib_psyntax.as_ptr(), self.lib_psyntax.len())
    }

    fn run_ops(&mut self, ops: *const Object) -> Object {
        self.sp = self.stack.as_mut_ptr();
        self.fp = self.sp;

        self.pc = ops;
        loop {
            let op: Op = unsafe { *self.pc }.to_instruction();
            self.pc = self.jump(self.pc, 1);
            match op {
                Op::CompileError => todo!(),
                Op::BranchNotLe => {
                    branch_number_cmp_op!(<=, self);
                }
                Op::BranchNotGe => {
                    branch_number_cmp_op!(>=, self);
                }
                Op::BranchNotLt => {
                    branch_number_cmp_op!(<, self);
                }
                Op::BranchNotGt => {
                    branch_number_cmp_op!(>, self);
                }
                Op::BranchNotNull => {
                    let skip_offset = self.isize_operand();
                    let op_result = self.ac.is_nil();
                    self.set_return_value(Object::make_bool(op_result));
                    if op_result {
                        // go to then.
                    } else {
                        // Branch and jump to else.
                        self.pc = self.jump(self.pc, skip_offset - 1);
                    }
                }
                Op::BranchNotNumberEqual => {
                    branch_number_cmp_op!(==, self);
                }
                Op::BranchNotEq => {
                    let skip_offset = self.isize_operand();
                    let pred = self.pop().eq(&self.ac);
                    self.set_return_value(Object::make_bool(pred));
                    if !pred {
                        // Branch and jump to else.
                        self.pc = self.jump(self.pc, skip_offset - 1);
                    }
                }
                Op::BranchNotEqv => {
                    let skip_offset = self.isize_operand();
                    if self.pop().eqv(&self.ac) {
                        self.set_return_value(Object::True);
                    } else {
                        self.pc = self.jump(self.pc, skip_offset - 1);
                        self.set_return_value(Object::False);
                    }
                }
                Op::BranchNotEqual => {
                    let skip_offset = self.isize_operand();
                    let e = Equal::new();
                    let x = self.pop();
                    if e.is_equal(&mut self.gc, &x, &self.ac) {
                        self.set_return_value(Object::True);
                    } else {
                        self.pc = self.jump(self.pc, skip_offset - 1);
                        self.set_return_value(Object::False);
                    }
                }
                Op::Append2 => {
                    let head = self.pop();
                    if Pair::is_list(head) {
                        let p = self.gc.append2(head, self.ac);
                        self.set_return_value(p);
                    } else {
                        self.arg_err("append", "pair", head);
                    }
                }
                Op::Call => {
                    let argc = self.isize_operand();
                    self.call_op(argc);
                }
                Op::Apply => todo!(),
                Op::Push => {
                    self.push_op();
                }
                Op::AssignFree => {
                    let n = self.usize_operand();
                    let closure = self.dc.to_closure();
                    match closure.refer_free(n) {
                        Object::Vox(mut vox) => {
                            vox.value = self.ac;
                        }
                        _ => {
                            panic!("assign_free: vox not found")
                        }
                    }
                }
                Op::AssignGlobal => {
                    let symbol = self.symbol_operand();
                    // Same as define global op.
                    self.define_global_op(symbol);
                }
                Op::AssignLocal => {
                    let n = self.isize_operand();
                    match self.refer_local(n) {
                        Object::Vox(mut vox) => vox.value = self.ac,
                        _ => {
                            panic!("assign_local: vox not found")
                        }
                    }
                }
                Op::Box => {
                    let n = self.isize_operand();
                    let vox = self.gc.alloc(Vox::new(self.index(self.sp, n)));
                    self.index_set(self.sp, n, Object::Vox(vox));
                }
                Op::Caar => match self.ac {
                    Object::Pair(pair) => match pair.car {
                        Object::Pair(pair) => {
                            self.set_return_value(pair.car);
                        }
                        obj => {
                            self.arg_err("caar", "pair", obj);
                        }
                    },
                    obj => {
                        self.arg_err("caar", "pair", obj);
                    }
                },
                Op::Cadr => match self.ac {
                    Object::Pair(pair) => match pair.cdr {
                        Object::Pair(pair) => {
                            self.set_return_value(pair.car);
                        }
                        obj => {
                            self.arg_err("cadr", "pair", obj);
                        }
                    },
                    obj => {
                        self.arg_err("cadr", "pair", obj);
                    }
                },
                Op::Car => {
                    self.car_op();
                }
                Op::Cdar => match self.ac {
                    Object::Pair(pair) => match pair.car {
                        Object::Pair(pair) => {
                            self.set_return_value(pair.cdr);
                        }
                        obj => {
                            self.arg_err("cdar", "pair", obj);
                        }
                    },
                    obj => {
                        self.arg_err("cdar", "pair", obj);
                    }
                },
                Op::Cddr => match self.ac {
                    Object::Pair(pair) => match pair.cdr {
                        Object::Pair(pair) => {
                            self.set_return_value(pair.cdr);
                        }
                        obj => {
                            self.arg_err("cddr", "pair", obj);
                        }
                    },
                    obj => {
                        self.arg_err("cddr", "pair", obj);
                    }
                },
                Op::Cdr => {
                    self.cdr_op();
                }
                Op::Closure => {
                    self.closure_op();
                    // TODO: Tentative GC here.
                    self.mark_and_sweep();
                }
                Op::Cons => {
                    let car = self.pop();
                    let cdr = self.ac;
                    let pair = self.gc.cons(car, cdr);
                    self.set_return_value(pair);
                }
                Op::Constant => {
                    self.constant_op();
                }
                Op::DefineGlobal => {
                    let symbol = self.symbol_operand();
                    self.define_global_op(symbol)
                }
                Op::Display => {
                    let num_free_vars = self.isize_operand();
                    let mut free_vars = vec![];
                    let start = self.dec(self.sp, 1);
                    for i in 0..num_free_vars {
                        let var = unsafe { *start.offset(-i) };
                        free_vars.push(var);
                    }
                    let mut display = self.gc.alloc(Closure::new(
                        [].as_ptr(),
                        0,
                        0,
                        false,
                        free_vars,
                        Object::False,
                    ));
                    display.prev = self.dc;

                    let display = Object::Closure(display);
                    self.dc = display;
                    self.sp = self.dec(self.sp, num_free_vars);
                }
                Op::Enter => {
                    let n = self.isize_operand();
                    self.enter_op(n)
                }
                Op::Eq => {
                    let ret = self.pop().eq(&self.ac);
                    self.set_return_value(Object::make_bool(ret));
                }
                Op::Eqv => {
                    let ret = self.pop().eqv(&self.ac);
                    self.set_return_value(Object::make_bool(ret));
                }
                Op::Equal => {
                    let e = Equal::new();
                    let val = self.pop();
                    let ret = e.is_equal(&mut self.gc, &val, &self.ac);
                    self.set_return_value(Object::make_bool(ret));
                }
                Op::Frame => {
                    self.frame_op();
                }
                Op::Indirect => match self.ac {
                    Object::Vox(vox) => {
                        self.set_return_value(vox.value);
                    }
                    obj => {
                        self.arg_err("indirect", "vox", obj);
                    }
                },
                Op::Leave => {
                    let n = self.isize_operand();
                    let sp = self.dec(self.sp, n);

                    match self.index(sp, 0) {
                        Object::ObjectPointer(fp) => {
                            self.fp = fp;
                        }
                        obj => {
                            panic!("leave: fp expected but got {:?}", obj);
                        }
                    }
                    self.dc = self.index(sp, 1);
                    self.sp = self.dec(sp, 2);
                }
                Op::LetFrame => {
                    let _unused = self.operand();
                    // TODO: expand stack.
                    self.push(self.dc);
                    self.push(Object::ObjectPointer(self.fp));
                }
                Op::List => todo!(),
                Op::LocalJmp => {
                    let jump_offset = self.isize_operand();
                    self.pc = self.jump(self.pc, jump_offset - 1);
                }
                Op::MakeContinuation => {
                    let _n = self.isize_operand();
                    let dummy = self.gc.new_string("TODO:continuation");
                    self.set_return_value(dummy);
                }
                Op::MakeVector => match self.pop() {
                    Object::Number(size) => {
                        let v = vec![self.ac; size as usize];
                        let v = self.gc.new_vector(&v);
                        self.set_return_value(v);
                    }
                    obj => {
                        self.arg_err("make-vector", "numbers", obj);
                    }
                },
                Op::Nop => {}
                Op::Not => {
                    self.set_return_value(Object::make_bool(self.ac.is_false()));
                }
                Op::NullP => {
                    self.set_return_value(Object::make_bool(self.ac.is_nil()));
                }
                Op::NumberAdd => {
                    self.number_add_op();
                }
                Op::NumberEqual => {
                    number_cmp_op!(==, self);
                }
                Op::NumberGe => {
                    number_cmp_op!(>=, self);
                }
                Op::NumberGt => {
                    number_cmp_op!(>, self);
                }
                Op::NumberLe => {
                    number_cmp_op!(<=, self);
                }
                Op::NumberLt => {
                    number_cmp_op!(<, self);
                }
                Op::NumberMul => match (self.pop(), self.ac) {
                    (Object::Number(a), Object::Number(b)) => {
                        self.set_return_value(Object::Number(a * b));
                    }
                    (a, b) => {
                        panic!("+: numbers required but got {:?} {:?}", a, b);
                    }
                },
                Op::NumberDiv => match (self.pop(), self.ac) {
                    (Object::Number(a), Object::Number(b)) => {
                        self.set_return_value(Object::Number(a / b));
                    }
                    (a, b) => {
                        panic!("/: numbers required but got {:?} {:?}", a, b);
                    }
                },
                Op::NumberSub => {
                    self.number_sub_op();
                }
                Op::PairP => self.set_return_value(Object::make_bool(self.ac.is_pair())),
                Op::Read => todo!(),
                Op::ReadChar => match self.ac {
                    Object::StringInputPort(mut port) => match port.read_char() {
                        Some(c) => {
                            self.set_return_value(Object::Char(c));
                        }
                        None => {
                            self.set_return_value(Object::Eof);
                        }
                    },
                    obj => {
                        self.arg_err("read-char", "text-input-port", obj);
                    }
                },
                Op::Reduce => todo!(),
                Op::ReferFree => {
                    let n = self.usize_operand();
                    self.refer_free_op(n);
                }
                Op::ReferGlobal => {
                    let symbol = self.symbol_operand();
                    self.refer_global_op(symbol);
                    //println!("symbol={}", Object::Symbol(symbol));
                }
                Op::ReferLocal => {
                    let n = self.isize_operand();
                    self.refer_local_op(n)
                }
                Op::RestoreContinuation => todo!(),
                Op::Return => {
                    let n = self.isize_operand();
                    self.return_n(n);
                }
                Op::SetCar => match self.pop() {
                    Object::Pair(mut pair) => {
                        pair.car = self.ac;
                        self.set_return_value(Object::Unspecified);
                    }
                    obj => {
                        self.arg_err("set-car!", "pair", obj);
                    }
                },
                Op::SetCdr => match self.pop() {
                    Object::Pair(mut pair) => {
                        pair.cdr = self.ac;
                        self.set_return_value(Object::Unspecified);
                    }
                    obj => {
                        self.arg_err("set-cdr!", "pair", obj);
                    }
                },
                Op::Shift => todo!(),
                Op::SymbolP => {
                    self.set_return_value(Object::make_bool(self.ac.is_symbol()));
                }
                Op::Test => {
                    let jump_offset = self.isize_operand();
                    if self.ac.is_false() {
                        self.pc = self.jump(self.pc, jump_offset - 1);
                    }
                }
                Op::Values => {
                    //  values stack layout
                    //    (value 'a 'b 'c 'd)
                    //    ==>
                    //    =====
                    //      a
                    //    =====
                    //      b
                    //    =====
                    //      c    [ac_] = d
                    //    =====
                    //  values are stored in [valuez vector] and [a-reg] like following.
                    //  #(b c d)
                    //  [ac_] = a
                    let n = self.usize_operand();

                    if n > MAX_NUM_VALUES + 1 {
                        panic!("values too many values {}", n);
                    } else {
                        self.num_values = n;

                        for i in (1..n).rev() {
                            self.values[i - 1] = self.ac;
                            self.ac = self.index(self.sp, (n - i - 1) as isize);
                        }

                        if n > 1 {
                            self.sp = self.dec(self.sp, self.num_values as isize - 1);
                        } else {
                            // there's no need to push
                        }
                    }
                    if n == 0 {
                        self.ac = Object::Unspecified;
                    }
                }
                Op::Receive => {
                    let num_req_args = self.usize_operand();
                    let num_opt_args = self.usize_operand();
                    if self.num_values < num_req_args {
                        panic!(
                            "receive: received fewer valeus than expected {} {}",
                            num_req_args, self.num_values
                        );
                    } else if num_opt_args == 0 && self.num_values > num_req_args {
                        panic!(
                            "receive: received more values than expected {} {}",
                            num_req_args, self.num_values
                        );
                    }
                    // (receive (a b c) ...)
                    if num_opt_args == 0 {
                        if num_req_args > 0 {
                            self.push(self.ac);
                        }
                        for i in 0..num_req_args - 1 {
                            self.push(self.values[i]);
                        }
                    // (receive a ...)
                    } else if num_req_args == 0 {
                        let mut ret = if self.num_values == 0 {
                            Object::Nil
                        } else {
                            self.gc.list1(self.ac)
                        };
                        for i in 0..self.num_values - 1 {
                            ret = Pair::append_destructive(ret, self.gc.list1(self.values[i]));
                        }
                        self.push(ret);
                    // (receive (a b . c) ...)
                    } else {
                        let mut ret = Object::Nil;
                        self.push(self.ac);
                        for i in 0..self.num_values - 1 {
                            if i < num_req_args - 1 {
                                self.push(self.values[i]);
                            } else {
                                ret = Pair::append_destructive(ret, self.gc.list1(self.values[i]));
                            }
                        }
                        self.push(ret);
                    }
                }
                Op::UnfixedJump => todo!(),
                Op::Stop => todo!(),
                Op::Shiftj => {
                    let depth = self.isize_operand();
                    let diff = self.isize_operand();
                    let display_count = self.isize_operand();

                    // SHIFT for embedded jump which appears in named let optimization.
                    //   Two things happens.
                    //   1. SHIFT the stack (same as SHIFT operation)
                    //   2. Restore fp and c registers.
                    //      This is necessary for jump which is across let or closure boundary.
                    //      new-fp => new-sp - arg-length
                    //
                    self.sp = self.shift_args_to_bottom(self.sp, depth, diff);
                    self.fp = self.dec(self.sp, depth);
                    let mut i = display_count;
                    loop {
                        if i <= 0 {
                            break;
                        }
                        self.dc = self.dc.to_closure().prev;
                        i -= 1;
                    }
                }
                Op::Undef => {
                    self.set_return_value(Object::Unspecified);
                }
                Op::VectorLength => match self.ac {
                    Object::Vector(v) => {
                        self.set_return_value(Object::Number(v.len() as isize));
                    }
                    obj => {
                        self.arg_err("vector-length", "vector", obj);
                    }
                },
                Op::VectorP => match self.ac {
                    Object::Vector(_) => {
                        self.set_return_value(Object::True);
                    }
                    _ => {
                        self.set_return_value(Object::False);
                    }
                },
                Op::VectorRef => match (self.pop(), self.ac) {
                    (Object::Vector(v), Object::Number(idx)) => {
                        let idx = idx as usize;
                        if idx < v.data.len() {
                            self.set_return_value(v.data[idx]);
                        } else {
                            self.arg_err("vector-ref", "valid idx to vector", self.ac);
                        }
                    }
                    (a, b) => {
                        panic!(
                            "vecto-ref: vector and number required but got {:?} {:?}",
                            a, b
                        );
                    }
                },
                Op::VectorSet => {
                    let n = self.pop();
                    let obj = self.pop();
                    match (obj, n) {
                        (Object::Vector(mut v), Object::Number(idx)) => {
                            let idx = idx as usize;
                            if idx < v.data.len() {
                                v.data[idx] = self.ac;
                            } else {
                                self.arg_err("vector-set", "valid idx to vector", obj);
                            }
                        }
                        (a, b) => {
                            panic!(
                                "vecto-set: vector and number required but got {:?} {:?}",
                                a, b
                            );
                        }
                    }
                }
                Op::PushEnter => {
                    self.push_op();
                    let n = self.isize_operand();
                    self.enter_op(n);
                }
                Op::Halt => {
                    break;
                }
                Op::ConstantPush => {
                    self.constant_op();
                    self.push_op();
                }
                Op::NumberSubPush => {
                    self.number_sub_op();
                    self.push_op();
                }
                Op::NumberAddPush => {
                    self.number_add_op();
                    self.push_op();
                }
                Op::PushConstant => {
                    self.push_op();
                    self.constant_op();
                }
                Op::PushFrame => {
                    self.push_op();
                    self.frame_op();
                }
                Op::CarPush => {
                    self.car_op();
                    self.push_op();
                }
                Op::CdrPush => {
                    self.cdr_op();
                    self.push_op();
                }
                Op::ShiftCall => todo!(),
                Op::NotTest => {
                    let jump_offset = self.isize_operand();
                    self.ac = if self.ac.is_false() {
                        Object::True
                    } else {
                        Object::False
                    };
                    if self.ac.is_false() {
                        self.pc = self.jump(self.pc, jump_offset - 1);
                    }
                }
                Op::ReferGlobalCall => {
                    let symbol = self.symbol_operand();
                    let argc = self.isize_operand();
                    self.refer_global_op(symbol);
                    self.call_op(argc);
                }
                Op::ReferFreePush => {
                    let n = self.usize_operand();
                    self.refer_free_op(n);
                    self.push_op();
                }
                Op::ReferLocalPush => {
                    let n = self.isize_operand();
                    self.refer_local_op(n);
                    self.push_op();
                }
                Op::ReferLocalPushConstant => {
                    let n = self.isize_operand();
                    self.refer_local_op(n);
                    self.push_op();
                    self.constant_op();
                }
                Op::ReferLocalPushConstantBranchNotLe => {
                    let n = self.isize_operand();
                    self.refer_local_op(n);
                    self.push_op();
                    self.constant_op();
                    branch_number_cmp_op!(<=, self);
                }
                Op::ReferLocalPushConstantBranchNotGe => {
                    let n = self.isize_operand();
                    self.refer_local_op(n);
                    self.push_op();
                    self.constant_op();
                    branch_number_cmp_op!(>=, self);
                }
                Op::ReferLocalPushConstantBranchNotNumberEqual => todo!(),
                Op::ReferLocalBranchNotNull => {
                    let n = self.isize_operand();
                    self.refer_local_op(n);
                    let skip_offset = self.isize_operand();
                    self.branch_not_null_op(skip_offset);
                }
                Op::ReferLocalBranchNotLt => {
                    let n = self.isize_operand();
                    self.refer_local_op(n);
                    branch_number_cmp_op!(<, self);
                }
                Op::ReferFreeCall => {
                    let n = self.usize_operand();
                    let argc = self.isize_operand();
                    self.refer_free_op(n);
                    self.call_op(argc);
                }
                Op::ReferGlobalPush => {
                    let symbol = self.symbol_operand();
                    self.refer_global_op(symbol);
                    self.push_op();
                    // println!("symbol={}", Object::Symbol(symbol));
                }
                Op::ReferLocalCall => {
                    let n = self.isize_operand();
                    let argc = self.isize_operand();
                    self.refer_local_op(n);
                    self.call_op(argc);
                }
                Op::LocalCall => {
                    let argc = self.isize_operand();
                    // Locall is lighter than Call
                    // We can omit checking closure type and arguments length.
                    match self.ac {
                        Object::Closure(c) => {
                            self.dc = self.ac;
                            // todo
                            //self.cl = self.ac;
                            self.pc = c.ops;
                            self.fp = self.dec(self.sp, argc);
                        }
                        obj => {
                            panic!("LocalCall: Bug {}", obj)
                        }
                    }
                }
                Op::Vector => {
                    let n = self.usize_operand();
                    let mut v = vec![Object::Unspecified; n];
                    let mut arg = self.ac;
                    if n > 0 {
                        let mut i = n - 1;
                        loop {
                            if i == 0 {
                                break;
                            }
                            v[i] = arg;
                            arg = self.pop();
                            i -= 1;
                        }
                        v[0] = arg;
                    }
                    let vec = self.gc.new_vector(&v);
                    self.set_return_value(vec);
                }
                Op::SimpleStructRef => match (self.pop(), self.ac) {
                    (Object::SimpleStruct(s), Object::Number(idx)) => {
                        self.set_return_value(s.data[idx as usize]);
                    }
                    (obj1, obj2) => {
                        panic!(
                            "simple-struct-ref: simple-struct and idx required but got {} {}",
                            obj1, obj2
                        );
                    }
                },
                Op::DynamicWinders => todo!(),
                Op::TailCall => {
                    let depth = self.isize_operand();
                    let diff = self.isize_operand();
                    self.sp = self.shift_args_to_bottom(self.sp, depth, diff);
                    let argc = depth;
                    self.call_op(argc);
                }
                Op::LocalTailCall => {
                    let depth = self.isize_operand();
                    let diff = self.isize_operand();
                    self.sp = self.shift_args_to_bottom(self.sp, depth, diff);
                    let closure = self.ac.to_closure();
                    let argc = depth;
                    self.dc = self.ac;
                    self.pc = closure.ops;
                    self.fp = self.dec(self.sp, argc);
                }
            }
            self.print_vm(op);
            //self.pc = self.jump(self.pc, 1);
        }
        self.ac
    }

    #[inline(always)]
    fn closure_op(&mut self) {
        let size = self.usize_operand();
        let arg_len = self.isize_operand();
        let is_optional_arg = self.bool_operand();
        let num_free_vars = self.isize_operand();
        let _max_stack = self.operand();
        let src_info = self.operand();
        let mut free_vars = vec![];
        let start = self.dec(self.sp, 1);
        for i in 0..num_free_vars {
            let var = unsafe { *start.offset(-i) };
            free_vars.push(var);
        }
        // Don't call self.alloc here.
        // Becase it can trigger gc and free the allocated object *before* it is rooted.
        let c = self.gc.alloc(Closure::new(
            self.pc,
            size - 1,
            arg_len,
            is_optional_arg,
            free_vars,
            src_info,
        ));
        self.set_return_value(Object::Closure(c));
        self.sp = self.dec(self.sp, num_free_vars);
        self.pc = self.jump(self.pc, size as isize - 6);
    }

    #[inline(always)]
    fn bool_operand(&mut self) -> bool {
        self.operand().to_bool()
    }

    #[inline(always)]
    fn isize_operand(&mut self) -> isize {
        self.operand().to_number()
    }

    #[inline(always)]
    fn symbol_operand(&mut self) -> GcRef<Symbol> {
        self.operand().to_symbol()
    }

    #[inline(always)]
    fn usize_operand(&mut self) -> usize {
        self.operand().to_number() as usize
    }

    #[inline(always)]
    fn push_op(&mut self) {
        self.push(self.ac);
    }
    #[inline(always)]
    fn frame_op(&mut self) {
        // Call frame in stack.
        // ======================
        //          pc*
        // ======================
        //          dc
        // ======================
        //          cl
        // ======================
        //          fp
        // ======== sp ==========
        //
        // where pc* = pc + skip_offset -1
        let skip_offset = self.operand().to_number();
        let next_pc = self.jump(self.pc, skip_offset - 1);
        self.make_frame(next_pc);
    }

    #[inline(always)]
    fn make_frame(&mut self, next_pc: *const Object) {
        self.push(Object::ProgramCounter(next_pc));
        self.push(self.dc);
        // TODO: This should be cl register.
        self.push(self.dc);
        self.push(Object::ObjectPointer(self.fp));
    }

    #[inline(always)]
    fn constant_op(&mut self) {
        let v = self.operand();
        self.set_return_value(v);
    }

    pub fn set_symbol_value(&mut self, symbol: GcRef<Symbol>, value: Object) {
        self.globals.insert(symbol, value);
    }

    fn define_global_op(&mut self, symbol: GcRef<Symbol>) {
        self.globals.insert(symbol, self.ac);
    }

    #[inline(always)]
    fn number_sub_op(&mut self) {
        match (self.pop(), self.ac) {
            (Object::Number(a), Object::Number(b)) => {
                self.set_return_value(Object::Number(a - b));
            }
            (a, b) => {
                panic!("-: numbers required but got {:?} {:?}", a, b);
            }
        }
    }

    #[inline(always)]
    fn number_add_op(&mut self) {
        match (self.pop(), self.ac) {
            (Object::Number(a), Object::Number(b)) => {
                self.set_return_value(Object::Number(a + b));
            }
            (a, b) => {
                panic!("+: numbers required but got {:?} {:?}", a, b);
            }
        }
    }

    #[inline(always)]
    fn enter_op(&mut self, n: isize) {
        self.fp = self.dec(self.sp, n);
    }

    #[inline(always)]
    fn branch_not_null_op(&mut self, skip_offset: isize) {
        if self.ac.is_nil() {
            self.set_return_value(Object::True);
        } else {
            self.set_return_value(Object::False);
            self.pc = self.jump(self.pc, skip_offset - 1);
        }
    }

    #[inline(always)]
    fn refer_free_op(&mut self, n: usize) {
        let val = self.dc.to_closure().refer_free(n);
        self.set_return_value(val);
    }

    #[inline(always)]
    fn car_op(&mut self) {
        match self.ac {
            Object::Pair(pair) => {
                self.set_return_value(pair.car);
            }
            obj => {
                self.arg_err("car", "pair", obj);
            }
        }
    }

    #[inline(always)]
    fn refer_local_op(&mut self, n: isize) {
        let obj = self.refer_local(n);
        self.set_return_value(obj);
    }

    #[inline(always)]
    fn refer_global_op(&mut self, symbol: GcRef<Symbol>) {
        match self.globals.get(&symbol) {
            Some(&value) => {
                self.set_return_value(value);
            }
            None => {
                panic!("identifier {} not found", symbol.string);
            }
        }
    }

    #[inline(always)]
    fn cdr_op(&mut self) {
        match self.ac {
            Object::Pair(pair) => {
                self.set_return_value(pair.cdr);
            }
            obj => {
                self.arg_err("cdr", "pair", obj);
            }
        }
    }

    #[inline(always)]
    fn call_op(&mut self, argc: isize) {
        let mut argc = argc;
        'call: loop {
            match self.ac {
                Object::Closure(closure) => {
                    self.dc = self.ac;
                    // TODO:
                    // self.cl = self.ac;
                    self.pc = closure.ops;
                    if closure.is_optional_arg {
                        let extra_len = argc - closure.argc;
                        if -1 == extra_len {
                            let sp = self.unshift_args(self.sp, 1);
                            self.index_set(sp, 0, Object::Nil);
                            self.sp = sp;
                            self.fp = self.dec(self.sp, closure.argc);
                        } else if extra_len >= 0 {
                            let args = self.stack_to_pair(extra_len + 1);
                            self.index_set(self.sp, extra_len, args);
                            let sp = self.dec(self.sp, extra_len);
                            self.fp = self.dec(sp, closure.argc);
                            self.sp = sp;
                        } else {
                            panic!(
                                "call: wrong number of arguments {} required bug got {}",
                                closure.argc, argc
                            );
                        }
                    } else if argc == closure.argc {
                        self.fp = self.dec(self.sp, argc);
                    } else {
                        panic!(
                            "call: wrong number of arguments {} required bug got {}",
                            closure.argc, argc
                        );
                    }
                }
                Object::Procedure(procedure) => {
                    let start = unsafe { self.sp.offset_from(self.stack.as_ptr()) } - argc;
                    let start: usize = start as usize;
                    let uargc: usize = argc as usize;
                    let args = &mut self.stack[start..start + uargc];

                    // copying args here because we can't borrow.
                    let args = &mut args.to_owned()[..];

                    // We convert apply call to Op::Call.
                    if procedure.func as usize == procs::apply as usize {
                        if argc == 1 {
                            panic!("apply: need two or more arguments but only 1 argument");
                        }
                        self.sp = self.dec(self.sp, argc);
                        self.ac = args[0];
                        // (apply proc arg1 arg2 ... args-as-list)
                        // We push arguments here. The last argument is flatten list.
                        for i in 1..argc {
                            if i == argc - 1 {
                                let mut last_pair = args[i as usize];
                                if !last_pair.is_list() {
                                    panic!(
                                        "apply: last arguments shoulbe proper list but got {}",
                                        last_pair
                                    );
                                }
                                let mut j: isize = 0;
                                loop {
                                    if last_pair.is_nil() {
                                        argc = argc - 2 + j;
                                        continue 'call;
                                    } else {
                                        match last_pair {
                                            Object::Pair(pair) => {
                                                self.push(pair.car);
                                                last_pair = pair.cdr;
                                            }
                                            _ => {
                                                panic!("never reached");
                                            }
                                        }
                                    }
                                    j = j + 1;
                                }
                            } else {
                                self.push(args[i as usize]);
                            }
                        }
                    } else if procedure.func as usize == procs::eval as usize {
                        self.ret_code = vec![];
                        self.ret_code.push(Object::Instruction(Op::Return));
                        self.ret_code.push(Object::Number(argc));

                        self.pc = self.ret_code.as_ptr();
                        (procedure.func)(self, args);
                    } else {
                        // TODO: Take care of cl.
                        // self.cl = self.ac

                        self.ac = (procedure.func)(self, args);
                        // TODO is this right??
                        self.return_n(argc);
                    }
                }
                _ => {
                    panic!("can't call {:?}", self.ac);
                }
            }
            break;
        }
    }

    fn reset_roots(&mut self) {
        // Clean up display closure so that Objects in ops can be freed.
        let mut closure = self.dc.to_closure();
        closure.ops = null();
        closure.ops_len = 0;
    }

    // Helpers.
    fn pop(&mut self) -> Object {
        unsafe {
            self.sp = self.dec(self.sp, 1);
            *self.sp
        }
    }

    fn push(&mut self, value: Object) {
        unsafe {
            *self.sp = value;
            self.sp = self.inc(self.sp, 1);
        }
    }

    fn index(&self, sp: *mut Object, n: isize) -> Object {
        unsafe { *self.dec(sp, n + 1) }
    }

    fn index_set(&mut self, sp: *mut Object, n: isize, obj: Object) {
        unsafe { *self.dec(sp, n + 1) = obj }
    }

    fn stack_len(&self) -> usize {
        unsafe { self.sp.offset_from(self.stack.as_ptr()) as usize }
    }

    #[cfg(feature = "debug_log_vm")]
    fn print_vm(&mut self, op: Op) {
        println!("-----------------------------------------");
        println!("{} executed", op);
        println!("  ac={}", self.ac);
        println!("  dc={}", self.dc);
        println!("-----------------------------------------");
        let fp_idx = unsafe { self.fp.offset_from(self.stack.as_ptr()) };
        for i in 0..self.stack_len() {
            println!(
                "  {}{}",
                self.stack[i],
                if fp_idx == i.try_into().unwrap() {
                    "  <== fp"
                } else {
                    ""
                }
            );
        }
        println!("-----------------------------------------<== sp")
    }
    #[cfg(not(feature = "debug_log_vm"))]
    fn print_vm(&mut self, _: Op) {}

    #[inline(always)]
    fn set_return_value(&mut self, obj: Object) {
        self.ac = obj;
        self.num_values = 1;
    }

    #[inline(always)]
    fn refer_local(&mut self, n: isize) -> Object {
        unsafe { *self.fp.offset(n) }
    }

    #[inline(always)]
    fn jump(&self, pc: *const Object, offset: isize) -> *const Object {
        unsafe { pc.offset(offset) }
    }

    #[inline(always)]
    fn operand(&mut self) -> Object {
        let obj = unsafe { *self.pc };
        let next_pc = self.jump(self.pc, 1);
        self.pc = next_pc;
        //unsafe { *next_pc }
        return obj;
    }

    #[inline(always)]
    fn inc(&self, pointer: *mut Object, offset: isize) -> *mut Object {
        unsafe { pointer.offset(offset) }
    }

    #[inline(always)]
    fn dec(&self, pointer: *mut Object, offset: isize) -> *mut Object {
        unsafe { pointer.offset(-offset) }
    }

    fn arg_err(&self, who: &str, expected: &str, actual: Object) {
        panic!("{}: requires {} but got {}", who, expected, actual);
    }

    fn return_n(&mut self, n: isize) {
        #[cfg(feature = "debug_log_vm")]
        println!("  return {}", n);
        let sp = self.dec(self.sp, n);
        match self.index(sp, 0) {
            Object::ObjectPointer(fp) => {
                self.fp = fp;
            }
            obj => {
                panic!("not fp pointer but {}", obj)
            }
        }
        // TODO: Take care of cl register.
        // self.cl = index(sp, 1);
        self.dc = self.index(sp, 2);
        match self.index(sp, 3) {
            Object::ProgramCounter(next_pc) => {
                self.pc = next_pc;
            }
            _ => {
                panic!("not a pc");
            }
        }
        self.sp = self.dec(sp, 4);
    }

    fn shift_args_to_bottom(&mut self, sp: *mut Object, depth: isize, diff: isize) -> *mut Object {
        let mut i = depth - 1;
        while i >= 0 {
            self.index_set(sp, i + diff, self.index(self.sp, i));
            i = i - 1;
        }
        self.dec(sp, diff)
    }

    fn unshift_args(&mut self, sp: *mut Object, diff: isize) -> *mut Object {
        for i in 0..diff {
            self.index_set(self.inc(sp, diff - i), 0, self.index(sp, 1));
        }
        self.inc(sp, diff)
    }

    fn stack_to_pair(&mut self, n: isize) -> Object {
        let mut args = Object::Nil;
        for i in 0..n {
            args = self.gc.cons(self.index(self.sp, i), args);
        }
        args
    }

    pub fn set_rtd(&mut self, key: Object, rtd: Object) {
        self.rtds.insert(key, rtd);
    }

    pub fn lookup_rtd(&self, key: Object) -> Object {
        match self.rtds.get(&key) {
            Some(&value) => value,
            _ => Object::False,
        }
    }

    pub fn set_global_value(&mut self, key: GcRef<Symbol>, value: Object) {
        self.globals.insert(key, value);
    }

    pub fn global_value(&mut self, key: GcRef<Symbol>) -> Option<&Object> {
        self.globals.get(&key)
    }

    pub fn current_input_port(&self) -> Object {
        self.current_input_port
    }

    pub fn set_current_input_port(&mut self, port: Object) {
        self.current_input_port = port;
    }

    pub fn read(&mut self) -> Result<Object, ReadError> {
        match self.current_input_port {
            Object::FileInputPort(mut port) => port.read(&mut self.gc),
            _ => {
                panic!(
                    "read: input-port required but got {}",
                    self.current_input_port
                )
            }
        }
    }
    pub fn eval_after(&mut self, sexp: Object) -> Object {
        let name = self.gc.symbol_intern("compile");
        let v = self.call_by_name(name, sexp).to_vector(); //self.compile(sexp).to_vector();
        let code_size = v.len();
        let body_size = code_size + 2;

        self.eval_code = vec![];
        for i in 0..code_size {
            self.eval_code.push(v.data[i]);
        }
        self.eval_code.push(Object::Instruction(Op::Return));
        self.eval_code.push(Object::Number(0));
        // todo: Should share this!
        let free_vars = default_free_vars(&mut self.gc);
        let c = self.gc.alloc(Closure::new(
            self.eval_code.as_ptr(),
            body_size,
            0,
            false,
            free_vars,
            Object::False,
        ));

        return self.set_after_trigger0(Object::Closure(c));
    }

    pub fn set_after_trigger0(&mut self, closure: Object) -> Object {
        self.make_frame(self.pc);
        self.trigger0_code[1] = closure;
        self.pc = self.trigger0_code.as_ptr();
        return self.ac;
    }

    fn call_by_name(&mut self, name: Object, arg: Object) -> Object {
        self.call_by_name_code[3] = arg;
        self.call_by_name_code[6] = name;
        self.evaluate_safe(self.call_by_name_code.as_ptr())
    }

    fn evaluate_safe(&mut self, ops: *const Object) -> Object {
        self.save_registers();
        let ret = self.evaluate_unsafe(ops);
        self.restore_registers();
        ret
    }

    fn evaluate_unsafe(&mut self, ops: *const Object) -> Object {
        self.closure_for_evaluate.to_closure().ops = ops;
        self.ac = self.closure_for_evaluate;
        self.dc = self.closure_for_evaluate;
        self.fp = null_mut();
        self.run_ops(ops)
    }


}
