use std::fmt::{self, Display};

use crate::{
    gc::GcRef,
    objects::{Object, Symbol},
};

#[derive(Copy, Clone, Debug, PartialEq)]
pub enum Op {
    NumberAdd,
    Append2,
    AssignFree(usize),
    AssignGlobal(GcRef<Symbol>),
    AssignLocal(isize),
    Box(isize),
    BranchNotEq(isize),
    BranchNotEqual(isize),
    BranchNotEqv(isize),
    BranchNotGe(isize),
    BranchNotGt(isize),
    BranchNotLe(isize),
    BranchNotLt(isize),
    BranchNotNull(isize),
    BranchNotNumberEqual(isize),
    Caar,
    Cadr,
    Call(isize),
    Car,
    CarPush,
    Cdar,
    Cddr,
    Cdr,
    CdrPush,
    Cons,
    Constant(Object),
    ConstantPush(Object),
    Closure {
        size: usize,
        arg_len: isize,
        is_optional_arg: bool,
        num_free_vars: isize,
    },
    DefineGlobal(GcRef<Symbol>),
    Display(isize),
    Enter(isize),
    Eq,
    Equal,
    Eqv,
    Frame(isize),
    Halt,
    Indirect,
    Leave(isize),
    LetFrame(isize),
    List(usize),
    LocalCall(isize),
    LocalJmp(isize),
    LocalTailCall(isize, isize),
    MakeContinuation(isize),
    MakeVector,
    Nop,
    Not,
    NotTest(isize),
    NullP,
    NumberAddPush,
    NumberDiv,
    NumberEqual,
    NumberGe,
    NumberGt,
    NumberLe,
    NumberLt,
    NumberMul,
    NumberSub,
    NumberSubPush,
    PairP,
    Push,
    PushConstant(Object),
    PushEnter(isize),
    PushFrame(isize),
    ReadChar,
    Receive(usize, usize),
    ReferFree(usize),
    ReferFreeCall(usize, isize),
    ReferFreePush(usize),
    ReferGlobal(GcRef<Symbol>),
    ReferGlobalCall(GcRef<Symbol>, isize),
    ReferGlobalPush(GcRef<Symbol>),
    ReferLocal(isize),
    ReferLocalBranchNotLt(usize, isize),
    ReferLocalBranchNotNull(isize, isize),
    ReferLocalCall(isize, isize),
    ReferLocalPush(isize),
    ReferLocalPushConstant(isize, Object),
    ReferLocalPushConstantBranchNotLe(isize, Object, isize),
    ReferLocalPushConstantBranchNotGe(isize, Object, isize),
    Return(isize),
    SetCar,
    SetCdr,
    Shiftj(isize, isize, isize),
    SimpleStructRef,
    SymbolP,
    TailCall(isize, isize),
    Test(isize),
    Undef,
    Values(usize),
    Vector(usize),
    VectorLength,
    VectorP,
    VectorRef,
    VectorSet,
}

impl Display for Op {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Op::DefineGlobal(sym) => {
                write!(f, "DefineGlobal({})", unsafe { sym.pointer.as_ref() })
            }
            Op::ReferGlobal(sym) => {
                write!(f, "ReferGlobal({})", unsafe { sym.pointer.as_ref() })
            }
            Op::ReferGlobalCall(sym, n) => {
                write!(f, "ReferGlobalCall({}, {})", unsafe { sym.pointer.as_ref() }, n)
            }  
            Op::ReferGlobalPush(sym) => {
                write!(f, "ReferGlobalPush({}", unsafe { sym.pointer.as_ref() })
            }                         
            _ => {
                write!(f, "{:?}", self)
            }
        }
    }
}

#[cfg(test)]
pub mod tests {

    use std::ptr;

    use super::*;
    use crate::gc::Gc;

    struct TestVm<'a> {
        ops: &'a [Op],
        pc: *const Op,
    }

    impl<'a> TestVm<'a> {
        fn run(&mut self, ops: &'a [Op]) -> Object {
            self.ops = ops;
            let mut val = Object::Unspecified;
            for i in 0..ops.len() {
                match ops[i] {
                    Op::Constant(n) => {
                        val = n;
                    }
                    _ => {
                        panic!("{:?} not supported", ops[i]);
                    }
                }
            }
            val
        }

        fn run_pc(&mut self, start_pc: *const Op, len: usize) -> Object {
            self.pc = start_pc;
            let mut val = Object::Unspecified;
            let mut pc = start_pc;
            for _ in 0..len {
                match unsafe { *pc } {
                    Op::Constant(n) => {
                        val = n;
                    }
                    op => {
                        panic!("{:?} not supported", op);
                    }
                }
                pc = unsafe { pc.offset(1) };
            }
            val
        }
    }

    fn print_slice_refs(s1: &[Op], s2: &[Op], s3: &[Op]) {
        println!("{:?} {:?} {:?}", s1, s2, s3);
    }

    // This tests if *const Op is good enough for vm.run arguments.
    #[test]
    fn test_op_pointer() {
        let mut gc = Gc::new();
        let mut vm = TestVm {
            pc: ptr::null(),
            ops: &[],
        };
        let array_ops = [
            Op::Constant(Object::Number(1)),
            Op::Constant(Object::Number(2)),
            Op::Constant(Object::Number(3)),
            Op::Constant(Object::Number(4)),
        ];

        // Have 1 pointer.
        let pc: *const Op = &array_ops[1] as *const Op;
        match unsafe { *pc } {
            Op::Constant(c) => {
                assert_eq!(c, Object::Number(2));
            }
            _ => {
                panic!("not supported.")
            }
        }
        // Have one more pointer.
        let pc2: *const Op = &array_ops[2] as *const Op;
        match unsafe { (*pc, *pc2) } {
            (Op::Constant(c), Op::Constant(d)) => {
                assert_eq!(c, Object::Number(2));
                assert_eq!(d, Object::Number(3));
            }
            _ => {
                panic!("not supported.")
            }
        }

        // Can mark Op but we can't know the lengths of the ops.
        gc.mark_op(unsafe { *pc });

        // Run the VM.
        match vm.run_pc(pc, 2) {
            Object::Number(n) => {
                assert_eq!(n, 3);
            }
            _ => {
                panic!("error");
            }
        }
    }

    // This tests if &[Op] is good enough for vm.run argument.
    #[test]
    fn test_vec_slice_op() {
        let mut gc = Gc::new();
        let mut vm = TestVm {
            pc: ptr::null(),
            ops: &[],
        };
        let vec_ops = vec![
            Op::Constant(Object::Number(1)),
            Op::Constant(Object::Number(2)),
            Op::Constant(Object::Number(3)),
            Op::Constant(Object::Number(4)),
        ];

        // Hold one slice ref.
        let slice_ref: &[Op] = &vec_ops[1..3];
        assert_eq!(slice_ref.len(), 2);
        assert_eq!(slice_ref[0], Op::Constant(Object::Number(2)));

        // Still can access original vec.
        assert_eq!(vec_ops.len(), 4);

        // Have different slice.
        let slice_ref2: &[Op] = &vec_ops[2..3];
        assert_eq!(slice_ref2.len(), 1);
        assert_eq!(slice_ref2[0], Op::Constant(Object::Number(3)));

        // Have sub slice_ref.
        let sub_slice_ref: &[Op] = &slice_ref[1..2];
        assert_eq!(sub_slice_ref.len(), 1);
        assert_eq!(sub_slice_ref[0], Op::Constant(Object::Number(3)));

        // Can pass refs to function.
        print_slice_refs(slice_ref, slice_ref2, sub_slice_ref);
        // Can still access the refs.
        print_slice_refs(slice_ref, slice_ref2, sub_slice_ref);

        // Can mark Op.
        gc.mark_op(slice_ref[0]);

        // Run the VM.
        vm.run(slice_ref);
        vm.run(slice_ref2);
        vm.run(sub_slice_ref);
    }

    #[test]
    fn test_array_slice_op() {
        let mut vm = TestVm {
            pc: ptr::null(),
            ops: &[],
        };
        let mut gc = Gc::new();
        let array_ops = [
            Op::Constant(Object::Number(1)),
            Op::Constant(Object::Number(2)),
            Op::Constant(Object::Number(3)),
            Op::Constant(Object::Number(4)),
        ];

        // Hold one slice ref.
        let slice_ref: &[Op] = &array_ops[1..3];
        assert_eq!(slice_ref.len(), 2);
        assert_eq!(slice_ref[0], Op::Constant(Object::Number(2)));

        // Still can access original array.
        assert_eq!(array_ops.len(), 4);

        // Have different slice.
        let slice_ref2: &[Op] = &array_ops[2..3];
        assert_eq!(slice_ref2.len(), 1);
        assert_eq!(slice_ref2[0], Op::Constant(Object::Number(3)));

        // Have sub slice_ref.
        let sub_slice_ref: &[Op] = &slice_ref[1..2];
        assert_eq!(sub_slice_ref.len(), 1);
        assert_eq!(sub_slice_ref[0], Op::Constant(Object::Number(3)));

        // Can pass refs to function.
        print_slice_refs(slice_ref, slice_ref2, sub_slice_ref);
        // Can still access the refs.
        print_slice_refs(slice_ref, slice_ref2, sub_slice_ref);

        // Can mark Op through ref.
        gc.mark_op(slice_ref[0]);

        // Run the VM.
        vm.run(slice_ref);
        vm.run(slice_ref2);
        vm.run(sub_slice_ref);
    }
}
