#lang scribble/base

@(require
"../assignment/assignment-mlang.rkt"
scriblib/figure
(for-label cpsc411/reference/a9-solution)
(for-label (except-in cpsc411/compiler-lib compile))
cpsc411/langs/v8
cpsc411/langs/v9
(for-label cpsc411/langs/v9))

@(provide (all-defined-out))

@declare-exporting[cpsc411/reference/a9-solution]
@(define sb
   (make-cached-eval
    "ch9-eval"
    '(require racket/pretty cpsc411/reference/a9-solution cpsc411/compiler-lib)))

@title[#:tag "top" #:tag-prefix "chp-closures:"]{Closures: Code is Data}
@(define (v8-tech . rest)
  (apply tech #:tag-prefixes '("book:" "chp-structured-data:") rest))

@section{Preface: What's wrong with Exprs-Lang v8?}
Actually, not much.
With structured data types, @v8-tech{Exprs-lang v8} is a pretty good language
now.

@v8-tech{Exprs-bits-lang/contexts v8} is sufficiently expressive to act as a reasonable
compiler backend for many languages.
It's roughly equivalent to C, although with more curvy parens.

@v8-tech{Exprs-lang v8} adds safety on top of that language, although this
safety does come at a cost.
The main limitation in @v8-tech{Exprs-lang v8} is the lack of abstractions over computation.
We have lots of abstraction over data, but it's common to want to abstract
over computation---first class functions, objects, function pointers, etc.
@v8-tech{Exprs-lang v8} prevents even passing function pointers to ensure safety.

In this chapter, we add the ability to easily abstract over computations at any point
via first-class procedures.
Many languages provide some version of this---Python, JavaScript, Ruby, Racket,
Scheme, Java, and many more.
They enable the programmer to create a suspended computation, and pass it around
as a value.
The procedure closes over the environment in which it was created, capturing any
free variables and essentially
creating an object with private fields.
They can be used as the foundations for object systems, and provide a safe,
lexically scoped alternative to function pointers.

In @deftech{Exprs-lang v9}, we add first-class procedures as values:
@bettergrammar*-ndiff[
#:labels ("v8 Diff (excerpts)" "Full")
(#:exclude (fixnum uint8 ascii-char-literal) exprs-lang-v8 exprs-lang-v9)
(exprs-lang-v9)
]

Now, @exprs-lang-v9[lambda] can appear in any expression.
We can still define procedures at the top-level using @exprs-lang-v9[define],
although the semantics will change slightly.

This is a syntactically small change, but it has massive implications.

@section{Closures and Closure Conversion}
So far, procedures in our language have been compiled directly to labeled
@deftech{code}---suspended computation that is closed execpt for it's declared
parameters.
We have not treated procedures as values, nor considered what happens if a
procedure appears in value context.
The closest representation of the value of a procedure we had was the label to
its @tech{code}.
In our source language, we disallowed passing procedures as values, to ensure
safety.

To support first-class procedures, we need to compile procedures to a more
sophisticated data structure.
We compile procedures to a data structure representing a @deftech{closure}, a
procedure paired with the values of free variables from the environment in which
the procedure was created.
This allows us to pass the procedure as data, and for us to create procedures
that refer to variables outside of their own scope.

Until now, all procedures were bound at the top-level in a set of
mutually-recursive definitions.
To work with first-class procedures in intermediate languages, we need to be
able to represent sets of mutually recursive definitions that appear @emph{as
expressions}.
We introduce the @closure-lang-v9[letrec] construct to aid with this.
@closure-lang-v9[(letrec ([aloc e] ...) e_2)] binds each @closure-lang-v9[aloc]
in each @closure-lang-v9[e], including its own right-hand-side, as well as
binding all @closure-lang-v9[aloc]s in @closure-lang-v9[e_2].
For now, we only consider a restricted form of @closure-lang-v9[letrec] that
only binds procedures.

We represent a @tech{closure} essentially as a vector containing a label to the
@tech{code} and the values of each free variable in its @tech{environment}.
@tech{Closures} support two operations.
First, you can call a @tech{closure} with @closure-lang-v9[(closure-call e es ...)], which
essentially extracts the label from the @tech{closure} @closure-lang-v9[e]
and calls the procedure at that label with the argument @closure-lang-v9[(es ...)].
Second, you can dereference an @tech{environment} variable from the
@tech{closure} with @closure-lang-v9[(closure-ref e e_i)], extracting the value
at index @closure-lang-v9[e_i] from the @tech{environment} of the @tech{closure}
@closure-lang-v9[e].

Because we want to implement safe procedure application, we add a third field to
the @tech{closure}: its @deftech{arity}, the number of arguments expected by
the @tech{code} of the @tech{closure}.

The @tech{closure} interface is described below:
@itemlist[
@item{@closure-lang-v9[(make-closure e_label e_arity e_i ...)]

Creates a @tech{closure} whose @tech{code} is at label @closure-lang-v9[e_label],
which expects @closure-lang-v9[e_arity] number of arguments, and has the values
@closure-lang-v9[e_i] in its @tech{environment}.
}
@item{@closure-lang-v9[(closure-call e_c es ...)]

Safely call the @tech{closure} @closure-lang-v9[e_c], invoking its @tech{code}, with
the arguments @closure-lang-v9[(es ...)].}
@item{@closure-lang-v9[(closure-ref e_c e_i)]

Deference the value at index @closure-lang-v9[e_i] in the @tech{environment} of the
@tech{closure} @closure-lang-v9[e_c].
Since this dereference is only generated by the compiler, it always succeeds and
performs no dynamic checks.
The environment is 0-indexed.
}
]

Before we can perform @tech{closure conversion}, we must discover which variables in a
@closure-lang-v9[lambda] are @tech{free} with respect to the procedure's scope.
We first annotation all @closure-lang-v9[lambda] with their free variable sets.
@racketblock[
`(lambda (,alocs ...) ,e)
=>
`(lambda ,(info-set '() 'free (set-subtract (free-var e) alocs))
         (,alocs ...) ,e)
]
We add a pass to perform this just prior to @tech{closure conversion}.

A variable is considered @deftech{free} in a scope if it is not in the set
of variables bound by that scope, if it is referenced in any expression in
which the scope binds variables, and if the reference is not @tech{bound}.
A variable is @deftech{bound} if it is refernced inside a scope for which it is
declared in the set of variables bound by that scope.

In our languages, @closure-lang-v9[lambda], @closure-lang-v9[let], and
@closure-lang-v9[letrec] introduce new scopes.
Calcuating the free variables of an expression is relatively straightforward,
but we have to be careful with the binding structures of
@closure-lang-v9[letrec] and @closure-lang-v9[let].
@margin-note{Note that all variables are @tech{bound}, which is enforced by
@racket[check-exprs-lang], but they can be @tech{free} relative to a particular
scope.}

@deftech{Closure conversion} is the process of transforming all first-class
proeceudres into an explicit data structure representing the @tech{closure}.
There are two parts to @tech{closure conversion}:
@itemlist[
@item{Transform each @closure-lang-v9[lambda].
Each @closure-lang-v9[lambda] is transformed to take a new formal parameter, which
is its closure, and to be bound to a @closure-lang-v9[label] in its enclosing
@closure-lang-v9[letrec].
We can think of this as adding a @tt{this} or @tt{self} argument to each procedure.

The @ch3-tech{abstract location} to which the the @closure-lang-v9[lambda] was
previously bound must now be bound to a closure.
The closure has @emph{n + 1} fields, where @racket[n] is the number of free
variables in the @closure-lang-v9[lambda].
The first field is the label to which the closure's @tech{code} is bound.
The remaining fields are references to the lexical variables in the
@tech{environment} of the closure.

In essence, we transform
@racketblock[
`(letrec ([,x (lambda (,xs ...) (free (,ys ...)) ,es)] ...)
   ,e)
_=>
`(letrec ([,l (lambda (,c ,xs ...)
                (let ([,ys (closure-ref ,c ,i)] ...)
                  ,es))] ...)
    (cletrec ([,x (make-closure ,l ,(length xs) ,ys ...)] ...)
      ,e))
]
where @racket[l] is a fresh label and @racket[c] is a fresh abstract location.
The @closure-lang-v9[cletrec] form is like @closure-lang-v9[letrec]
but restricted to bind @tech{closures}.
We add the number of arguments as a field in the @tech{closure} to implement
safe application later.
}
@item{Transform each @closure-lang-v9[call].
Every procedure now takes an extra argument, its closure, so we have to expand
each @closure-lang-v9[call].
The essence of the translation is:
@racketblock[
`(call ,e ,es ...)
_=>
`(let ([,x ,e])
   (closure-call ,x ,x ,es ...))
]
We use @closure-lang-v9[closure-call] to call the (label of the) @tech{closure}
to the @tech{closure} itself and its usual arguments.
We need to bind the operator to avoid duplicating code.

}
]

The data structure will include the label to the procedure's @tech{code},
allowing us to compile labelled @tech{code} as before.

Every instance of @exprs-lang-v9[lambda] compiles to a procedure.
The procedure now has three pieces of information: its arity, the label to its
@deftech{code}, the computation it executes when invoked, and its
@deftech{environment}, the values of the free variables used in the definition
of the procedure.
We compile each application of a procedure to dereference and call the label of
the procedure, but also to pass a reference to the procedure itself as a parameter.
Essentially, the procedure is an object, and receives itself as an argument.
Each "free variable" @tt{x} is a field of that object, and are compiled to
references to @tt{self.x}.

We already have the low-level abstractions in place to deal with
@tech{closures}, so we design this assignment top-down.

@section{Administrative Passes}
Allowing procedures to be bound in two different ways is great for programmer
convenience, but annoying for a compiler writer.
Before we get to implementing procedures, we simplify and
regularize how procedures appear in our language.

@subsection{uniquify}
As usual with @racket[uniquify], the only change is that all names
@exprs-lang-v9[x] are replaced by abstract locations
@exprs-unique-lang-v9[aloc].

Unlike in previous versions, there are no @exprs-lang-v9[label]s after
@racket[uniquify].
All of our procedures are data, not merely code, and cannot easily be lifted to
the top level yet, so it is now the job of a later pass to introduce labels.

Below we define @deftech{Exprs-unique-lang v9}.
We typeset the changes with respect to @tech{Exprs-lang v9}.

@bettergrammar*-ndiff[
#:labels ("v8 Diff (excerpts)" "Source/Target Diff (excerpts)" "Full")
(#:exclude (prim-f aloc label fixnum uint8 ascii-char-literal)
  exprs-unique-lang-v8 exprs-unique-lang-v9)
(#:exclude (prim-f aloc label fixnum uint8 ascii-char-literal)
 exprs-lang-v9 exprs-unique-lang-v9)
(exprs-unique-lang-v9)
]

@defproc[(uniquify [p exprs-lang-v9]) exprs-unique-lang-v9]{
Resolves top-level @ch3-tech{lexical identifiers} into unique @ch2-tech{abstract
locations}.
}

@subsection{implement-safe-primops}
Not much changes in @racket[implement-safe-primops].

The target language of the pass, @deftech{Exprs-unsafe-data-lang v9}, is defined
below.

@bettergrammar*-ndiff[
#:labels ("v8 Diff (excerpts)" "Source/Target Diff (excerpts)" "Full")
(#:exclude (aloc label fixnum uint8 ascii-char-literal)
  exprs-unsafe-data-lang-v8 exprs-unsafe-data-lang-v9)
(#:exclude (aloc label fixnum uint8 ascii-char-literal)
  exprs-unique-lang-v9 exprs-unsafe-data-lang-v9)
(exprs-unsafe-data-lang-v9)
]

Note that this pass does not implement safe @exprs-unsafe-data-lang-v9[apply],
but can be safely applied to arbitrary data---a later pass will implement
dynamic checking for application.

@defproc[(implement-safe-primops [p exprs-unique-lang-v9?])
         exprs-unsafe-data-lang-v9?]{
Implement safe primitive procedures by inserting procedure definitions for each
primitive operation which perform dynamic tag checking, to ensure type and
memory safety.
}

@subsection{define->letrec}
Some procedures now appear in local expressions, and some appear defined at the
top-level.
This presents two problems.
First, we have to look for procedures in two different places to transform them:
that's annoying.
Second, our compiler later assumes that all @emph{data} (as opposed to code) is
@emph{locally} defined---we have no way to define top-level, labelled data.
Since procedures are data, we need to transform top-level bindings of procedures
into local bindings, so the rest of the compiler will "just work".

To do this, we elaborate @just-exprs-lang-v9[define] into a local binding form
@just-exprs-lang-v9[letrec], which will be used to bind all procedures.

@just-exprs-lang-v9[letrec], unlike @just-exprs-lang-v9[let], supports multiple bindings in a
single form, and each bound expression can refer to any variable in the set of
bindings for the @just-exprs-lang-v9[letrec].
This is important to capture mutually-recursive functions, and has the same
binding structure as our top-level @just-exprs-lang-v9[define]s.

@digression{
In general, a language might impose additional semantics on
@just-exprs-lang-v9[define], such as allowing @just-exprs-lang-v9[define]d data
to be exported and imported at module boundaries.
This would require additional handling of @just-exprs-lang-v9[define], and the ability
to generate labelled data in the back-end of the compiler.
We continue to ignore separate compilation and linking, so we treat
@just-exprs-lang-v9[define] as syntactic sugar for @just-exprs-lang-v9[letrec].
}

Below we define @deftech{Just-Exprs-lang v9}.

@bettergrammar*-ndiff[
#:labels ("Source/Target Diff (excerpts)" "Full")
(#:exclude (prim-f aloc label fixnum uint8 ascii-char-literal)
 exprs-unsafe-data-lang-v9 just-exprs-lang-v9)
(just-exprs-lang-v9)
]

@defproc[(define->letrec [p exprs-unsafe-data-lang-v9])
          just-exprs-lang-v9?]{
Elaborate top-level @exprs-unique-lang-v9[define]'s data into local recursively
bound data using @just-exprs-lang-v9[letrec].
}

@subsection{optimize-direct-calls}
Before we start compiling @just-exprs-lang-v9[lambda]s, we should try to get rid of
them.
@emph{Direct calls} to @just-exprs-lang-v9[lambda]s, such as @racket[(apply (lambda (x)
x) 1)], are simple to rewrite to a @just-exprs-lang-v9[let] binding, such a
@racket[(let ([x 1]) x)].
A human programmer may not write this kind of code much, but most programs are
not written by humans---compilers write far more programs.
This optimization will speed-up compile time and run time for such simple
programs.

@exercise{Design and implement the function @racket[optimize-direct-calls].
The source and target language are @tech{Just-Exprs-lang v9}.
}

@challenge{Direct calls are an instance of single-occurance procedures, which
always safe to inline.
Instead of dealing with them separately, we could design and implement a general
purpose inlining pass, and direct calls would simply be one of many calls
optimized.

Design and implement an inlining optimization.
}

@subsection{dox-lambdas}
The source language supports anonymous procedures, that is, first-class
procedure values that are not necessarily bound to names.
For example, we can write the following in Racket, creating and using procedures
without ever binding them to names in a @just-exprs-lang-v9[letrec] or
@just-exprs-lang-v9[let] form.
@examples[
((lambda (x f) (f x x)) 1 (lambda (x y) (+ x y)))
]

The equivalent in @tech{Exprs-lang v9} is:
@racketblock[
(call (lambda (x f) (apply f x x)) 1 (lambda (x y) (call + x y)))
]

First-class procedure values are great for functional programmers, who value
freedom, but bad for compilers who feel it is their job to keep track of
everything.

We want to bind all procedures to names to simplify lifting code to the
top-level and assigning labels later.

We transform each @racket[`(lambda (,alocs ...) ,e)] into @racket[`(letrec
([,tmp (lambda (,alocs ...) ,e)]) ,tmp)], where @racket[tmp] is a fresh
@just-exprs-lang-v9[aloc].

We define @deftech{Lam-opticon-lang v9}, in which we know the name of every
procedure.

@bettergrammar*-ndiff[
#:labels ("Source/Target Diff (excerpts)" "Full")
(#:exclude (prim-f aloc label fixnum uint8 ascii-char-literal)
 just-exprs-lang-v9 lam-opticon-lang-v9)
(lam-opticon-lang-v9)
]

@defproc[(dox-lambda [p just-exprs-lang-v9?])
         lam-opticon-lang-v9?]{
Explicitly binds all procedures to @ch3-tech{abstract locations}.
}

@section{Closure Conversion}
The rest of our compiler expects procedures to be little more than labeled
blocks of code.
Unfortunately, now our procedures can contain references to free-variables
in their lexical scope.
This means we cannot simply lift procedure definitions to the top-level, stick
on a label, and generate a labelled procedure.

@subsection{uncover-free}
First, we uncover the @tech{free} variables in each @lam-free-lang-v9[lambda].
We add these as an annotation on the @lam-free-lang-v9[lambda], which the next
pass will use to generate @tech{closures}.

Below we define @deftech{Lambda-free-lang v9}.
@bettergrammar*-ndiff[
#:labels ("Source/Target Diff (excerpts)" "Full")
(#:exclude (pred effect primop aloc label fixnum uint8 ascii-char-literal)
 lam-opticon-lang-v9 lam-free-lang-v9)
(lam-free-lang-v9)
]

To find the @tech{free} @ch3-tech{abstract locations}, we traverse the body of each
@lam-free-lang-v9[lambda] remembering any @ch3-tech{abstract locations} that
have been @tech{bound} (by @lam-free-lang-v9[let], @lam-free-lang-v9[lambda], or
@lam-free-lang-v9[letrec]), and return the set of @ch3-tech{abstract locations}
that have been used but were not in the defined set.
On entry to the @lam-free-lang-v9[(lambda (aloc ...) e)], only the formal parameters
@lam-free-lang-v9[(aloc ...)] are considered @tech{bound}.

@defproc[(uncover-free [p lam-opticon-lang-v9?])
         lam-free-lang-v9?]{
Explicitly annotate procedures with their free variable sets.
}

The only complicated case is for @lam-free-lang-v9[letrec].
Even a variable @tech{bound} in a @lam-free-lang-v9[letrec] is considered
@tech{free} in the body of a @lam-free-lang-v9[lambda].
@examples[#:eval sb
(uncover-free
 `(module
    (letrec ([x.1 (lambda () (call x.1))])
      x.1)))
]

However, the @closure-lang-v9[letrec] does bind those variables, so they do not
contribute to the free variable set for the context surrounding the
@closure-lang-v9[letrec].
@examples[#:eval sb
(uncover-free
 `(module
    (letrec ([f.1 (lambda ()
                    (letrec ([x.1 (lambda () (call x.1))])
                      x.1))])
      f.1)))
]

@subsection{convert-closures}
Now, we make @tech{closures} explicit.

Strictly speaking, all the previous languages had
@deftech{closures}---procedures that (implicitly) close over their lexical
environment.
However, our earlier languages forbid us from ever creating procedures that had
a non-empty set environment, so all our @tech{closures} were trivial to compile
to labelled code.
Closure conversion is the process of compiling first-class procedures into an
explicit data type.

Below, we define @deftech{Closure-lang v9}.

@bettergrammar*-ndiff[
#:labels ("Source/Target Diff (excerpts)" "Full")
(#:exclude (primop pred v effect aloc fixnum uint8 ascii-char-literal)
 lam-free-lang-v9 closure-lang-v9)
(closure-lang-v9)
]

Closure conversion changes @closure-lang-v9[letrec] to bind labels to procedure
code.
After this pass, the body of @closure-lang-v9[lambda] will not contain any free
variables, and will not be a procedure data type---it is just like a function
from @ch6-tech{Values-lang v6}.

To encode closures, we temporarily add a new data type for closures.
We add a new form, @closure-lang-v9[cletrec], which only binds closures.
Closures can, in general, have recursive self-references, so this is a variant
of the @closure-lang-v9[letrec] form.
We also add a new form for dereferencing the value of lexical variables
from the closure @closure-lang-v9[(closure-ref e e)].
The next pass implements closures using the procedure data type.

We assume that the @closure-lang-v9[cletrec] form only ever appears as the body of a
@closure-lang-v9[letrec] form, but we do not make this explicit in the syntax for
readability.
This assumption is not necessary for correctness, but simplifies an
optimization presented later as a challenge exercise.

We add @closure-lang-v9[unsafe-call] to the language to enable optimizing closures,
an important optimization in functional languages.
This @closure-lang-v9[unsafe-call] directly applies a label to arguments, without
performing any checks.
@closure-lang-v9[closure-call] will get translated into the safe, dynamically
checked call.

@defproc[(convert-closures [p lam-free-lang-v9?])
         closure-lang-v9?]{
Converts all procedures into explicit @tech{closures}.
}

@margin-note{
If the operator is already a @closure-lang-v9[aloc], avoid
avoid introducing an extra @closure-lang-v9[let]:
@racketblock[
`(call ,aloc ,es ...)
_=>
`(closure-call ,aloc ,aloc ,es ...)
]
This also simplifies the optimization @racket[optimize-known-calls].
}

@subsection{Challenge: optimize-known-call}
Closures can cause a lot of indirection, and thus performance penalty, in a
functional language.
We essentially transform all call into @emph{indirect calls}.
This causes an extra memory dereference and indirect jump, both of which can
have performance penalties.

Many calls, particularly to named functions, can be optimized to direct calls.
We essentially perform the following transformation on all calls where we can
determine the label of the operator:
@racketblock[
`(closure-apply ,e ,es ...)
_=>
`(unsafe-apply ,l ,es ...)
]
where @racket[l] is known to be the label of the closure @racket[e].
Because @racket[e] is already an @object-code{aloc}, we can safely discard it;
we do not need to force evaluation to preserve any side-effects.

Because this transforms into an @object-code{unsafe-apply}, we need to inline
the arity check that @racket[implement-safe-apply] would insert.
Something like:
@racketblock[
`(closure-apply ,e ,es ...)
_=>
`(if (eq? (procedure-arity e) ,(sub1 (length es)))
     (unsafe-apply ,l ,es)
     ,bad-arity-error)
]
Remember the the @object-code{procedure-arity} will be one more than the closure
arguments, since the closure takes itself as a hidden argument.
@margin-note{We could further optimize this, since we should know the arity
statically when this optimization would apply.}

We do this by recognizing @object-code{letrec} and @object-code{cletrec} as a
single composite form:
@racketblock[
`(letrec ([,label_l ,lam])
   (cletrec ([,aloc_c (make-closure ,label_c ,es ...)])
     ,e))
]
All references uses of @object-code{(closure-apply ,aloc_c ,es ...)} in
@racket[e] and @racket[lam] can be transformed into @object-code{(unsafe-apply
,label_c ,es ...)}.
We have to recognize these as a single composite form to optimize recursive
calls inside @racket[lam], which will benefit the most from the optimization.
This relies on the name @racket[aloc_c] being bound in two places: once to
define the closure, and once when dereferenced in a recursive closure.

@challenge{Design and implement the function @racket[optimize-known-calls].
The source and target language are @tech{Closure-lang v9}.
}

@subsection{hoist-lambdas}
Now that all @object-code{lambda}s are closed and labeled, we can lift them to
top-level @object-code{define}s.

We define @deftech{Hoisted-lang v9} below.
We typeset differences with respect to @tech{Closure-lang v9}.

@racketgrammar*[
[p     (module (unsyntax @bnf:add{b ...}) e)]
[(unsyntax @bnf:add{b}) (define label (lambda (aloc ...) e))]
[c     (begin c ...) (primop e ...)]
[e     v
       (primop e ...)
       (unsafe-apply e e ...)
       (let ([aloc e] ...) e)
       (unsyntax @bnf:sub{(letrec ([label (lambda (aloc ...)  e)] ...) e)})
       (cletrec ([aloc (make-closure label e e ...)] ...) e)
       (if e e e)
       (begin c ... e)]
[v     _...]
[primop _...]
]

The only difference is the @object-code{letrec} is remove and
@object-code{define} blocks are re-added.

@exercise{Design and implement the function @racket[hoist-lambdas].
The source language is @tech{Closure-lang v9} and the target language is
@tech{Hoisted-lang v9}.}

@subsection{implement-closures}
Now we implement closures as procedures.

@todo{Need to add proceudres now; removed from prior milestone}
@;@item{A @deftech{procedure} is a data structure representing a value that can be
@;called as a function.
@;Essentially, it is a wrapper around labels so we can check applications.
@;Starting in this language, application must use a procedure instead of
@;referencing a label directly.
@;We construct a procedure using @exprs-unsafe-data-lang-v8[(make-procedure e_1 e_2)], where
@;@exprs-unsafe-data-lang-v8[e_1] must evaluate to a label and @exprs-unsafe-data-lang-v8[e_2] is the number
@;of expected arguments.
@;The predicate @exprs-unsafe-data-lang-v8[procedure?] should return @exprs-unsafe-data-lang-v8[#t] for any
@;value constructed this way, and #f for any other value---@exprs-unsafee-data-lang-v8[(eq?
@;(procedure? (make-procedure e_1 e_2)) #t)].
@;We extract the label of a procedure with @exprs-unsafe-data-lang-v8[(unsafe-procedure-label
@;e_1)], where @exprs-unsafe-data-lang-v8[e_1] is a procedure.
@;We get the arity of a procedure with @exprs-unsafe-data-lang-v8[(unsafe-procedure-arity e_1)],
@;where @exprs-unsafe-data-lang-v8[e_1] is a procedure.
@;}
@;We remove @object-code{make-procedure} and @object-code{procedure-label}, which
@;are used internally.
@;The surface programmer will only be able to define safe procedures using
@;@object-code{lambda}.
@;However, we do allow the user to dynamically test whether a value is a procedure
@;and how many arguments it takes.


Our procedure object is going to be extended compared to last assignment.
Previously, we only had a label and an arity as part of a procedure.
All procedures were defined at the top-level and could not have lexical
variables.

Now, a procedure will look like an extension of a vector.
It will have at least three fields: the label, the arity, and a size.
The size indicates how large the environment of the procedure is.
The environment will be uninitialized after @object-code{make-procedure}, and
instead the environment will be initialized manually using
@object-code{unsafe-procedure-set!}, similar to vector initialization.
As before, @object-code{unsafe-procedure-label} and
@object-code{unsafe-procedure-arity} dereference the label and arity of a
procedure.
However, we now also have @object-code{unsafe-procedure-ref} which dereferences
a value from the procedure's environment, given an index into the environment,
similar to @object-code{unsafe-vector-ref}.
We still have a safe version of apply, @object-code{procedure-apply}.

The language @deftech{Proc-apply-lang v9} is defined below.
The changes are typeset with respect to @tech{Hoisted-lang v9}.

@racketgrammar*[
[p     (module b ... e)]
[b     (define label (lambda (aloc ...) e))]
[c     (begin c ...) (primop e ...)]
[e     v
       (primop e ...)
       (unsafe-apply e e ...)
       (let ([aloc e] ...) e)
       (unsyntax @bnf:sub{(cletrec ([aloc (make-closure label e ...)] ...) e)})
       (if e e e)
       (begin c ... e)]
[v     _...]
[primop _...
        (unsyntax @bnf:add{make-procedure})
        (unsyntax @bnf:add{unsafe-procedure-ref})
        (unsyntax @bnf:add{unsafe-procedure-set!})
        (unsyntax @bnf:add{procedure-apply})
        (unsyntax @bnf:sub{closure-ref})
        (unsyntax @bnf:sub{closure-apply})]
]

For reference, the procedure interface is described below:
@itemlist[
@item{@object-code{(make-procedure e_label e_arity e_size)}

Creates a procedure whose label is @object-code{e_label}, which expects
@object-code{e_arity} number of arguments, and has an environment of size
@object-code{e_size}.

@object-code{make-procedure} does not perform any error checking; it must be
applied to a label and two fixnum @a7-tech{ptrs}.
This is safe because no user can access @object-code{make-procedure}
directly.
Only the compiler generates uses of this operator, and surely our compiler uses
it correctly.
}
@item{@object-code{(unsafe-procedure-ref e_proc e_index)}

Return the value at index @object-code{e_index} in the environment of the
procedure @object-code{e_proc}.

As with all unsafe operators, this does not perform any checking.
}
@item{@object-code{(unsafe-procedure-set! e_proc e_index e_val)}

Set the value at index @object-code{e_index} in the environment of the
procedure @object-code{e_proc} to be @object-code{e_val}.
}
@item{@object-code{(procedure-apply e_proc es ...)}

Safely apply the procedure @object-code{e_proc} to its arguments
@object-code{es}.
Some later pass will implement this primop to check that @object-code{e_proc} is
a procedure that expects exactly @racket[(length es)] arguments.
}
]

To transform closures into procedures, we do a three simple translations:
@itemlist[
@item{Transform @object-code{make-closure}
@racketblock[
`(cletrec ([,aloc (make-closure ,label ,arity ,es ...)] ...)
   ,e)
_=>
`(let ([,aloc (make-procedure ,label ,arity ,n)] ...)
   (begin
     (unsafe-procedure-set! ,aloc 0 ,(list-ref es 0))
     ...
     (unsafe-procedure-set! ,aloc ,n ,(list-ref es n))
     ,e))
]
where @racket[n] is @racket[(length es)], the number of values in the
environment.
}
@item{Transform @object-code{closure-ref}.
@racketblock[
`(closure-ref ,c ,i)
_=>
`(unsafe-procedure-ref ,c ,i)
]
We can use @object-code{unsafe-procedure-ref} since we generate all uses of
@object-code{closure-ref}.
}
@item{Transform @object-code{closure-apply}.
@racketblock[
`(closure-apply ,c ,es ...)
_=>
`(procedure-apply ,c ,es ...)
]
@object-code{procedure-apply} must still be dynamically checked, since procedure
applications came from user programs.
}
]

@exercise{Design and implement the function @racket[implement-closures].
The source language is @tech{Hoisted-lang v9} and the target language is
@tech{Proc-apply-lang v9}.
}

@subsection{sequentialize-let}
Next we simplify the language once more by sequentializing @object-code{let}, so
each @object-code{let} binds exactly one abstract location.
It's not terribly important when we do this, but the rest of our compiler
assumes unary @object-code{let}, so we might as well do it now.

We define @deftech{Unary-let-lang v9}, typesetting the differences with respect
to @tech{Proc-apply-lang v9}.

@racketgrammar*[
[p     (module b ... e)]
[b     (define label (lambda (aloc ...) e))]
[c     (begin c ...) (primop e ...)]
[e     v
       (primop e ...)
       (unsafe-apply e e ...)
       (let ([aloc e] (unsyntax @bnf:sub{...})) e)
       (if e e e)
       (begin c ... e)]
[v     _...]
[primop _...
        make-procedure
        unsafe-procedure-ref
        unsafe-procedure-set!
        procedure-apply]
]

The translation is straightforward.

@exercise{Design and implement the function @racket[sequentialize-let].
The source language is @tech{Proc-apply-lang v9} and the target language is
@tech{Unary-let-lang v9}.
}

@subsection{implement-safe-apply}
Now we implement @object-code{procedure-apply} in terms of
@object-code{unsafe-apply}
@object-code{unsafe-procedure-label}, and
@object-code{unsafe-procedure-arity}.

Below we define @deftech{Exprs-data-lang v9}.
We typeset changes with respect to @tech{Unary-let-lang v9}.

@racketgrammar*[
[p     (module b ... e)]
[b     (define label (lambda (aloc ...) e))]
[c     (begin c ...) (primop e ...)]
[e     v
       (primop e ...)
       (unsyntax @bnf:sub{(unsafe-apply e e ...)})
       (unsyntax @bnf:add{(apply e e ...)})
       (let ([aloc e]) e)
       (if e e e)
       (begin c ... e)]
[v     _...]
[primop unsafe-fx* unsafe-fx+ unsafe-fx- eq? unsafe-fx< unsafe-fx<= unsafe-fx>
        unsafe-fx>=
        fixnum? boolean? empty? void? ascii-char? error? not
        pair?
        procedure?
        vector?

        cons
        unsafe-car
        unsafe-cdr

        unsafe-make-vector
        unsafe-vector-length
        unsafe-vector-set!
        unsafe-vector-ref

        make-procedure
        unsafe-procedure-arity
        unsafe-procedure-label
        unsafe-procedure-ref
        unsafe-procedure-set!
        (unsyntax @bnf:sub{procedure-apply})]
]

We implement @object-code{procedure-apply} in terms of @object-code{procedure?},
@object-code{unsafe-procedure-label}, and @object-code{unsafe-procedure-arity}.
The essence of the transformation is:
@racketblock[
`(procedure-apply ,e ,es ...)
_=>
`(if (procedure? ,e)
     (if (eq? (unsafe-procedure-arity ,e) ,(sub1 (length es)))
         (apply (unsafe-procedure-label ,e) ,es ...)
         ,bad-arity-error)
     ,bad-proc-error)
]
We subtract one from the length of the parameter list to account for the closure
parameter.
We could equivalently add one to the procedure arity, but since the length of
the parameter list is known at compile-time, this saves us at least one run-time
instruction.

@digression{
This pass assumes the closure argument must always be there.
This design prevents us from optimizing away the closure parameter easily, a
slight annoyance that is due to your professor missing this design mistake
before releasing the assignment.
A better design would place this pass before closure conversion, exposing
@object-code{unsafe-apply} earlier.
Then we would have access to the correct arity count without the closure
argument, and closure conversion modify the @object-code{unsafe-apply} form
without disrupting @object-code{procedure-arity}.

We do not want to capture the closure parameter in the
@object-code{procedure-arity} value, since this value is exposed to a user, and
we do not want the user to know about the internal closure parameter.
This internal parameter is not part of their code, so we should not burden them
with it.
}

We change the name of @object-code{unsafe-apply} to @object-code{apply}, since
that's what the rest of the compiler uses.

Note that we cannot simply define @object-code{procedure-apply} as a procedure,
like we did with other safe wrappers, since it must count its arguments, and we
must support a variable number of arguments to the procedure.

@exercise{Design and implement the function @racket[implement-safe-apply].
The source language is @tech{Unary-let-lang v9} and the target language is
@tech{Exprs-data-lang v9}.
}

@subsection{specify-representation}
Finally, we need to modify the procedure data type slightly.
It was intentionally designed to be similar to the vector data type.

We define @deftech{Impure-Exprs-bits-lang v9} below.
There are no differences with respect to @a8-tech{Impure-Exprs-bits-lang v8}.

@racketgrammar*[
[p     (module b ... e)]
[b     (define label (lambda (aloc ...) e))]
[c     (begin c ...) (mset! e e e)]
[e     v
       (let ([aloc e]) e)
       (if (cmp e e) e e)
       (begin c ... e)
       (binop e e) (apply e e ...)
       (alloc e)
       (mref e e)]
[v     int64 label aloc]
[binop * + - bitwise-and bitwise-ior bitwise-xor arithmetic-shift-right]
[cmp   neq? eq? < <= > >=]
]

When implementing @object-code{make-procedure}, you may assume the size of the
environment is a fixnum constant.

@exercise{Redesign and extend the implementation of the function
@racket[specify-representation].
The source language is @tech{Exprs-data-lang v9} and the target language is
@tech{Impure-Exprs-bits-lang v9}.
}

No other passes should need to be updated.

@section{Appendix: Overview}

@define[v9-graph
@dot->svg{
digraph {

node [ shape="box", fontsize=12 ]


/* The Languages */

Lx [label="Exprs-lang v8"];
Ly [label="Exprs-unique-lang v8"];
Lz [label="Exprs-unsafe-data-lang v8"];
L0 [label="Exprs-bits-lang v8"];
L1 [label="Values-bits-lang v8"];
L2 [label="Proc-imp-mf-lang v8"];
L3 [label="Imp-mf-lang v8"];
L4 [label="Imp-cmf-lang v8"];
L5_1 [label="Asm-alloc-lang v8"];
L5 [label="Asm-pred-lang v8"];
L6 [label="Asm-pred-lang v8/locals"];
L7 [label="Asm-pred-lang v8/undead"];
L8 [label="Asm-pred-lang v8/conflicts"];
L81 [label="Asm-pred-lang v8/pre-framed"];
L82 [label="Asm-pred-lang v8/framed"];
L83 [label="Asm-pred-lang v8/spilled"];
L9 [label="Asm-pred-lang v8/assignments"];
L10 [label="Nested-asm-lang-fvars v8"];
L10_1 [label="Nested-asm-lang v8"];
L11 [label="Block-pred-lang v8"];
L12 [label="Block-asm-lang v8"];
L12_1 [label="Para-asm-lang v8"];
L14 [label="x64"];
L15 [label="integer"]

/* Register allocator */

edge [fontname="Courier", fontsize=12, labeljust=right]

L5 -> L6 [label=" uncover-locals"];
L6 -> L7 [label=" undead-analysis"];
L7 -> L8 [label=" conflict-analysis"];
L8 -> L81 [label= " assign-call-undead-variables"];
L81 -> L82 [label=" allocate-frames"];
L82 -> L83 [label=" assign-registers"];
L83 -> L9 [label=" assign-frame-variables"];
L9 -> L10 [label=" replace-locations"];

Lx -> Lx [label=" check-exprs-lang"];
Lx -> Ly [label=" uniquify"];
Ly -> Lz [label=" implement-safe-primops"];
Lz -> L0 [label=" specify-representation"];
L0 -> L1 [label=" remove-complex-opera*"];
L1 -> L2 [label=" sequentialize-let"];
L2 -> L3 [label=" impose-calling-conventions"]
L3 -> L4 [label=" canonicalize-bind"];
L4 -> L5_1 [label=" select-instructions"];
L5_1 -> L5 [label= " expose-allocation-pointer"];


L10 -> L10_1 [label=" implement-fvars"];
L10_1 -> L11 [label=" expose-basic-blocks"];
L11 -> L12 [label=" resolve-predicates"]
L12 -> L12_1 [label=" flatten-program"];
L12_1 -> L15_1 [label=" patch-instructions"];
L15_1 -> L16 [label=" implement-mops"];
L16 -> L14 [label=" generate-x64"];
L14 -> L15 [label=" execute"];

subgraph DoNotcluster1 {
  graph [labeljust=right,
    style=filled,
    color=lightgrey,
    fontname="Courier",
    fontsize=10,
    label = "interp-paren-x64";
  ];
  edge [fontname="Courier"]

  L15_1 [label="Paren-x64-mops v8"];
  L16 [label="Paren-x64 v8"];
  L17 [label="Paren-x64-rt v8"];
}

  L16 -> L17 [label=" link-paren-x64"];
  L17 -> L15 [label=" interp-loop"];
  L16 -> L15 [label=" interp-paren-x64"];
}
}
]
