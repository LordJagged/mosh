use crate::lexer::Spanned;
use crate::number_lexer::{NumberLexer, Token, NumberLexicalError};

/*!re2c
    re2c:define:YYCTYPE = usize; // We have Vec<char> and treat char as usize.
    re2c:define:YYPEEK = "*self.s.get_unchecked(self.cursor) as usize";
    re2c:define:YYSKIP = "self.cursor += 1;";
    re2c:define:YYBACKUP = "self.marker = self.cursor;";
    re2c:define:YYRESTORE = "self.cursor = self.marker;";
    re2c:define:YYLESSTHAN = "self.cursor >= self.limit";
    re2c:yyfill:enable = 0;
    re2c:eof = 0;

    // Conforms to R7RS.
    DIGIT                  = [0-9];
    HEX_DIGIT              = DIGIT | [A-Fa-f];
    DIGIT_10               = DIGIT;
    DIGIT_16               = HEX_DIGIT;
    INF_NAN                = "+inf.0" | "-inf.0" | "+nan.0" | "-nan.0";
    EXACTNESS              = ("#"[ie])?;
    SIGN                   = [\+\-]?;
    EXPONENT_MARKER        = "e";
    SUFFIX                 = (EXPONENT_MARKER SIGN (DIGIT_10)+)?;
    UINTEGER_10            = DIGIT_10 +;
    DECIMAL_10             = (UINTEGER_10 SUFFIX) | ("." (DIGIT_10)+ SUFFIX) | ((DIGIT_10)+ "." (DIGIT_10)* SUFFIX);
    UREAL_10               = UINTEGER_10 | (UINTEGER_10 "/" UINTEGER_10) | DECIMAL_10;
    REAL_10                = (SIGN UREAL_10) | INF_NAN;
    RADIX_10               = "#d" ?;
    COMPLEX_10             = REAL_10 | (REAL_10 "@" REAL_10) | (REAL_10 [\+\-] UREAL_10 'i') | (REAL_10 [\+\-] INF_NAN 'i') | (REAL_10 [\+\-] 'i') | ([\+\-] UREAL_10 'i') | ([\+\-] INF_NAN 'i') | ([\+\-] 'i');
    PREFIX_10              = (RADIX_10 EXACTNESS) | (EXACTNESS RADIX_10);
    NUM_10                 = PREFIX_10 COMPLEX_10;
    UINTEGER_16            = DIGIT_16 +;
    UREAL_16               = UINTEGER_16 | (UINTEGER_16 "/" UINTEGER_16);
    REAL_16                = (SIGN UREAL_16) | INF_NAN;
    RADIX_16               = "#x" ?;
    COMPLEX_16             = REAL_16 | (REAL_16 "@" REAL_16) | (REAL_16 [\+\-] UREAL_16 'i') | (REAL_16 [\+\-] INF_NAN 'i') | (REAL_16 [\+\-] 'i') | ([\+\-] UREAL_16 'i') | ([\+\-] INF_NAN 'i') | ([\+\-] 'i');
    PREFIX_16              = (RADIX_16 EXACTNESS) | (EXACTNESS RADIX_16);
    NUM_16                 = PREFIX_16 COMPLEX_16;
    EOS                    = "\X0000";
*/

impl<'input> Iterator for NumberLexer<'input> {
    type Item = Spanned<Token, usize, NumberLexicalError>;

    fn next(&mut self) -> Option<Self::Item> {
        loop {
            loop {
                self.tok = self.cursor;
                /*!re2c
                    DIGIT_10 {
                        println!("digit10 ");
                        return self.with_location(Token::Digit10 { value: self.extract_token() });
                    }
                    "/" { return self.with_location(Token::Slash); }
                    "+" { return self.with_location(Token::Plus); }
                    "-" { return self.with_location(Token::Minus); }
                    "." { return self.with_location(Token::Dot); }
                    "e" { return self.with_location(Token::Exponent); }
                    "i" { return self.with_location(Token::Imag); }
                    "#d" { return self.with_location(Token::Radix10); }
                    "#e" { return self.with_location(Token::Exact); }
                    "#i" { return self.with_location(Token::Inexact); }
                    "+inf.0" { return self.with_location(Token::PlusInf); }
                    "-inf.0" { return self.with_location(Token::MinusInf); }                    
                    $ { return None; }
                    * { return Some(Err(NumberLexicalError {
                            start: self.tok,
                            end: self.cursor,
                            token: self.extract_token()
                        })); }
                */
            }
        }
    }
}


