use crate::{
    gc::GcRef,
    objects::{Object, Symbol},
};

#[derive(Copy, Clone, Debug)]
pub enum Op {
    NumberAdd,
    AddPair,
    Append2,
    AssignFree(usize),
    AssignGlobal(GcRef<Symbol>),
    AssignLocal(isize),
    Box(isize),
    BranchNotGe(usize),
    BranchNotGt(usize),
    BranchNotLe(usize),    
    BranchNotLt(usize),
    BranchNotNull(usize),
    BranchNotNumberEqual(usize),
    Call(isize),
    Car,
    Cdr,
    Cadr,
    Cons,
    Constant(Object),
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
    Frame(usize),
    Halt,
    Indirect,
    Leave(isize),
    LetFrame(isize),
    LocalJmp(usize),
    MakeVector,
    VectorLength,
    Nop,
    Not,
    NullP,
    NumberEqual,
    NumberGe,
    NumberGt,
    NumberLe,
    NumberLt,
    PairP,
    Push,
    ReferFree(usize),
    ReferGlobal(GcRef<Symbol>),
    ReferLocal(isize),
    Return(isize),
    SetCar,
    SetCdr,
    SymbolP,
    TailCall(isize, isize),
    Test(usize),
    Undef,
}
