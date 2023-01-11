extern crate num_derive;
#[macro_use] extern crate lalrpop_util;

lalrpop_mod!(pub calculator1); // synthesized by LALRPOP
pub mod alloc;
pub mod compiler;
pub mod equal;
pub mod fasl;
pub mod gc;
pub mod objects;
pub mod op;
pub mod procs;
pub mod vm;

fn main() {}

use crate::vm::Vm;


#[test]
fn calculator1() {
    let mut vm = Vm::new();
    println!("{:?}", calculator1::DatumParser::new().parse(&mut vm.gc, "#t"));
    println!("{:?}", calculator1::DatumParser::new().parse(&mut vm.gc, "(#t)"));    
    //assert!(calculator1::TermParser::new().parse("#t").is_ok());
    //assert!(calculator1::TermParser::new().parse("#f").is_ok());
    //assert!(calculator1::TermParser::new().parse("#T").is_ok());
    //assert!(calculator1::TermParser::new().parse("#f").is_err());
}
