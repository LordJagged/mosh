use crate::lexer::{Lexer, Spanned, Token, LexicalError};
use std::str;
impl<'input> Iterator for Lexer<'input> {
    type Item = Spanned<Token, usize, LexicalError>;

    fn next(&mut self) -> Option<Self::Item> {
        self.tok = self.cursor;
'lex: loop {
    /*!re2c
        re2c:define:YYCTYPE = u8;
        re2c:define:YYPEEK = "*self.s.get_unchecked(self.cursor)";
        re2c:define:YYSKIP = "self.cursor += 1;";
        re2c:define:YYBACKUP = "self.marker = self.cursor;";
        re2c:define:YYRESTORE = "self.cursor = self.marker;";
        re2c:define:YYLESSTHAN = "self.cursor >= self.limit";
        re2c:yyfill:enable = 0;
        re2c:eof = 0;

        // Conforms R7RS.
        TRUE                   = "#t" | "#true";
        FALSE                  = "#f" | "#false";
        LETTER                 = [A-Za-z];
        SPECIAL_INITIAL        = [!\$%&\*\/\:\<=\>\?\^\_~];
        INITIAL                = LETTER | SPECIAL_INITIAL;
        DIGIT                  = [0-9];
        EXPLICIT_SIGN          = "+" | "-";
        SPECIAL_SUBSEQUENT     = EXPLICIT_SIGN | "." | "@";
        SUBSEQUENT             = INITIAL | DIGIT | SPECIAL_SUBSEQUENT;
        VERTICAL_LINE          = "|";
        HEX_DIGIT              = DIGIT | [A-Fa-f];         
        HEX_SCALAR_VALUE       = HEX_DIGIT +;        
        INLINE_HEX_ESCAPE      = "\\x" HEX_SCALAR_VALUE ";";            
        SIGN_SUBSEQUENT        = INITIAL | EXPLICIT_SIGN | "@";
        DOT_SUBSEQUENT         = SIGN_SUBSEQUENT | ".";
        // Per R7RS Small Errata, we allow \\\\ and \\\" here.
        MNEMONIC_ESCAPE        = ('\\' [abtnr\\\"]);   
        PECULIAR_IDENTIFIER    = EXPLICIT_SIGN | EXPLICIT_SIGN SIGN_SUBSEQUENT SUBSEQUENT * | EXPLICIT_SIGN "." DOT_SUBSEQUENT SUBSEQUENT * | "." DOT_SUBSEQUENT SUBSEQUENT *;
        SYMBOL_ELEMENT         = [^\|\\] | "\\|" | INLINE_HEX_ESCAPE | MNEMONIC_ESCAPE;        
        IDENTIFIER             = (INITIAL (SUBSEQUENT)*) | VERTICAL_LINE SYMBOL_ELEMENT * VERTICAL_LINE | PECULIAR_IDENTIFIER;
        LEFT_PAREN             = "(";
        RIGHT_PAREN            = ")";        
        RETURN                 = "\r";
        NEWLINE                = "\n";
        INTRA_LINE_WHITE_SPACE = " " | "\t";
        LINE_ENDING            = NEWLINE | RETURN NEWLINE | RETURN RETURN;
        WHITE_SPACE            = INTRA_LINE_WHITE_SPACE | LINE_ENDING;
        DELIMITER              = WHITE_SPACE | VERTICAL_LINE | LEFT_PAREN | RIGHT_PAREN | '"' | ";" | "\x00";
      
        // Doesn't conforms R7RS yet.  
        STRING_ELEMENT         = [^\"\\] | MNEMONIC_ESCAPE | '\\"' | '\\\\' | '\\' INTRA_LINE_WHITE_SPACE * LINE_ENDING INTRA_LINE_WHITE_SPACE * | INLINE_HEX_ESCAPE;
        STRING                 = '"' STRING_ELEMENT * '"';

        // Handlers
        LEFT_PAREN { println!("*** (");return return Some(Ok((0, Token::LeftParen, 2))); }
        RIGHT_PAREN { println!("*** )");return return Some(Ok((0, Token::RightParen, 2))); }        
        TRUE  {
            //self.cursor -= 1;
            return Some(Ok((0, Token::True, 2)));
        }
        FALSE  {
            //make
            //self.cursor -= 1;
            return Some(Ok((0, Token::False, 2)));
        }
        IDENTIFIER { println!("ident!!!!{:?}", str::from_utf8(&self.s[self.tok..self.cursor])); return Some(Ok((0, Token::Identifier{value: self.extract_token()}, 2)));}
        STRING {
            return Some(Ok((0, Token::String{value: self.extract_string()}, 2)));
        }
        DELIMITER {
            println!("WHITE SPACE");
            continue 'lex;
        }        
        $ { println!("$$$$");return  
        None; }
        * { println!("else else2 <{}>", self.extract_token());return  None; }
       */
}
    }
}


