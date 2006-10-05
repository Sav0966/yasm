%{
#include <time.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "tools/re2c/globals.h"
#include "tools/re2c/parse.h"

/* Work around bug in Bison 2.1 */
#define YYPARSE_PARAM	unused

int yylex(void);
void yyerror(const char*);

static unsigned int accept;
static RegExp *spec;
static Scanner *in;

%}

%start	spec

%union {
    Symbol	*symbol;
    RegExp	*regexp;
    Token	*token;
    char	op;
    ExtOp	extop;
}

%token		CLOSESIZE   CLOSE	ID	CODE	RANGE	STRING

%type	<op>		CLOSE
%type	<op>		close
%type	<extop>		CLOSESIZE
%type	<symbol>	ID
%type	<token>		CODE
%type	<regexp>	RANGE	STRING
%type	<regexp>	rule	look	expr	diff	term	factor	primary

%%

spec	:
		{ accept = 0;
		  spec = NULL; }
	|	spec rule
		{ spec = spec? mkAlt(spec, $2) : $2; }
	|	spec decl
	;

decl	:	ID '=' expr ';'
		{ if($1->re)
		      Scanner_fatal(in, "sym already defined");
		  $1->re = $3; }
	;

rule	:	expr look CODE
		{ $$ = RegExp_new_RuleOp($1, $2, $3, accept++); }
	;

look	:
		{ $$ = RegExp_new_NullOp(); }
	|	'/' expr
		{ $$ = $2; }
	;

expr	:	diff
		{ $$ = $1; }
	|	expr '|' diff
		{ $$ =  mkAlt($1, $3); }
	;

diff	:	term
		{ $$ = $1; }
	|	diff '\\' term
		{ $$ =  mkDiff($1, $3);
		  if(!$$)
		       Scanner_fatal(in, "can only difference char sets");
		}
	;

term	:	factor
		{ $$ = $1; }
	|	term factor
		{ $$ = RegExp_new_CatOp($1, $2); }
	;

factor	:	primary
		{ $$ = $1; }
	|	primary close
		{
		    switch($2){
		    case '*':
			$$ = mkAlt(RegExp_new_CloseOp($1), RegExp_new_NullOp());
			break;
		    case '+':
			$$ = RegExp_new_CloseOp($1);
			break;
		    case '?':
			$$ = mkAlt($1, RegExp_new_NullOp());
			break;
		    }
		}
	|	primary CLOSESIZE
		{
			$$ = RegExp_new_CloseVOp($1, $2.minsize, $2.maxsize);
		}
	;

close	:	CLOSE
		{ $$ = $1; }
	|	close CLOSE
		{ $$ = ($1 == $2) ? $1 : '*'; }
	;

primary	:	ID
		{ if(!$1->re)
		      Scanner_fatal(in, "can't find symbol");
		  $$ = $1->re; }
	|	RANGE
		{ $$ = $1; }
	|	STRING
		{ $$ = $1; }
	|	'(' expr ')'
		{ $$ = $2; }
	;

%%

void yyerror(const char* s){
    Scanner_fatal(in, s);
}

int yylex(){
    return Scanner_scan(in);
}

void line_source(FILE *o, unsigned int line)
{
    char *	fnamebuf;
    char *	token;

    if (iFlag)
	return;
    fprintf(o, "#line %u \"", line);
    if( fileName != NULL ) {
    	fnamebuf = mystrdup( fileName );
    } else {
	fnamebuf = mystrdup( "<stdin>" );
    }
    token = strtok( fnamebuf, "\\" );
    for(;;) {
	fprintf(o, "%s", token);
	token = strtok( NULL, "\\" );
	if( token == NULL ) break;
	fputs("\\\\", o);
    }
    fputs("\"\n", o); oline++;
    free( fnamebuf );
}

void parse(FILE *i, FILE *o){
    time_t now;

    time(&now);

    fputs("/* Generated by re2c 0.9.1-C on ", o);
    fprintf(o, "%-24s", ctime(&now));
    fputs(" */\n", o); oline+=2;

    in = Scanner_new(i);

    line_source(o, Scanner_line(in));

    while(Scanner_echo(in, o)){
	yyparse(NULL);
	if(spec)
	    genCode(o, spec);
	line_source(o, Scanner_line(in));
    }
}
