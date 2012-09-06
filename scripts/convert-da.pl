#!/usr/bin/env perl

use strict;
use warnings;
use v5.12;
use utf8;

use Lingua::CoNLLX;
use List::MoreUtils qw/any/;

my %posmap = qw/AC det
                AN adj
                AO adj
                CC konj
                CS sbu
                I  interj
                NC subst
                NP subst
                PC pron
                PD det
                PI det
                PO det
                PP pron
                PT pron
                RG adv
                SP prep
                VA verb
                VE verb
                XA subst
                XF subst
                XR subst
                XS symb
                XX ukjent/;

my %xpmap = (',' => '<komma>',
             '"' => '<anf>',
             '(' => '<parentes-beg>',
             ')' => '<parentes-slutt>',
             '-' => '<strek>');

my %featmap = (case => {nom => 'nom', gen => 'gen'},
               number => {sing => 'ent', plur => 'fl'},
               gender => {neuter => 'nøyt'}, # How to handle common & common/neuter
               def => {indef => 'ub', def => 'be'},
               definiteness => {indef => 'ub', def => 'be'},
               voice => {passive => 'pass'},
               register => {'polite' => 'høflig'},
               mood => {infin => 'inf', imper => 'imp'}, # XXX: Participles
               tense => {present => 'pres', past => 'pret'},
               reflexive => {yes => 'refl'},
               person => {1 => 1, 2 => 2, 3 => 3},
               degree => {pos => 'pos', comp => 'kom', sup => 'sup'},
           );

my %depmap = qw{aobj  ADV
                appa  APP
                appr  APP
                avobj ADV
                conj  KONJ
                coord KOORD
                dobj  DOBJ
                expl  FSUBJ
                iobj  IOBJ
                list  ATR
                lobj  ADV
                mod   ATR
                modo  ADV
                modp  APP
                modr  ATR
                mods  ADV
                name  APP
                namef ATR
                namel ATR
                numa  DET
                numm  DET
                obl   ADV
                part  ADV
                pnct  IK
                pobj  ADV
                possd possd
                pred  SPRED
                qobj  PAR
                subj  SUBJ
                title APP
                tobj  ADV
                vobj  INFV
                voc   PAR
                xpl   PAR
                xtop  APP};
                #err   ?
                #pnct  IP/IK
                #rel   ATR/ADV
                #rep   ?

my $corpus = Lingua::CoNLLX->new(file => $ARGV[0]);

for my $s (@{$corpus->sentences}) {
    $s->iterate(\&depmap);
    $s->iterate(\&fix_deps);
    $s->iterate(\&posmap);

    print $s, "\n\n";
}

sub depmap {
    my $w = $_;
    my $rel = $w->deprel;

    # Unroll chains of nobjs.
    my $x = $w;
    while($rel eq 'nobj') {
        $rel = $x->head->deprel;
        $x = $x->head;
    }
    return if $rel ne 'ROOT' and $rel =~ m/[A-Z]+/msxo; # Hack to handle already mapped rels.

    $rel = $1 if $rel =~ m/\A < (.+) > \z/msxo;

    # Hack, hack, hack.
    $rel = "rel" if $rel eq 'vobj' and lc($w->head->form) eq 'som' and $w->head->postag eq 'U';

    if(exists $depmap{$rel}) {
        $rel = $depmap{$rel};
    }
    elsif(lc($w->form) eq 'som' and $w->postag eq 'U') {
        $rel = 'SBUREL';
    }
    elsif($rel eq 'ROOT') {
        my $pos = $w->postag;
        $rel = $pos eq 'I'? 'INTERJ': 'FINV';
    }
    elsif($rel eq 'rel') {
        my $headpos = $w->head->postag;
        $rel = $headpos eq 'RG' || $headpos eq 'SP' ? 'ADV': 'ATR';
    }
    else {
        $rel = "$rel???";
    }

    $w->deprel($rel);
}

sub posmap {
    # TODO: Feature conversion?
    my $w = $_;
    my $pos = $w->postag;

    if(exists $posmap{$pos}) {
        $pos = $posmap{$pos};
    }
    elsif($pos eq 'U') {
        $pos = $w->form eq 'at'? 'inf-merke': 'sbu';
    }
    elsif($pos eq 'XP') {
        #if form is ',': <komma>, elsif form is '"': <anf>,
        # elsif form is '(': <parentes-beg>, elsif form is ')':
        # <parentes-slutt>, elsif form is '-': <strek>, else: clb 
        $pos = $xpmap{$w->form} || 'clb';
    }
    else {
        die "Can't convert $pos.\n"
    }

    if($w->feats) {
        my %feats = map { split m/=/msxo } @{$w->feats};
        my @new;

        # TODO: Handle special-cased stuff here.
        # TODO: exists $feats{possessor} => set poss
        # TODO: Use transcat feature for <pres-part>
        while(my ($key, $value) = each %feats) {
            if(exists $featmap{$key}{$value}) {
                push @new, $featmap{$key}{$value};
            }
        }

        $w->feats(@new? \@new : undef);
    }

    $w->postag($pos);
    $w->cpostag($pos);
}

sub fix_deps {
    my $w = $_;
    my $pos = $w->postag;
    my $rel = $w->deprel;

    # genitive construction
    if($rel eq 'possd') {
        my $head = $w->head;
        my $headhead = $head->head;

        # In DDT, genitives are the heads of the possesed, while in the
        # Norwegian treebank we want the possessed to be the head.
        $headhead->_delete_child($head);
        $head->_delete_child($w);

        $headhead->_add_child($w);
        $w->_add_child($head);

        $head->head($w);
        $w->head($headhead);

        $w->deprel($head->deprel);
        $head->deprel('DET');
    }
    # coordination
    elsif($rel eq 'KOORD' and $w->form eq 'og') {
        my @children = grep { $_->deprel eq 'KONJ' } @{$w->children};
        return if @children != 1; # 46 coords have no conj children. We ignore those

        my $head = $w->head;
        my $conj = $children[0];

        $head->_delete_child($w);
        $w->_delete_child($conj);

        $head->_add_child($conj);
        $conj->_add_child($w);

        $w->head($conj);
        $conj->head($head);
    }
    # possible determiner construction
    elsif($rel eq 'nobj') {
        my $cpos = $w->cpostag;
        my $head = $w->head;
        my $headpos = $head->postag;
        my $headcpos = $head->cpostag;

        # We only convert nobj constructions headed by a P (pronoun), N
        # (noun), or A (adjective). All of them are determiner-like
        # constructions.
        return if $cpos ne 'N' or ($headcpos ne 'P' and $headcpos ne 'N' and
            $headcpos ne 'A');

        my $headhead = $head->head;
        $head->_delete_child($w);
        $headhead->_delete_child($head);

        # Attach any other children of the determiner to the word instead.
        for my $adj (@{$head->children}) {
            $head->_delete_child($adj);
            $w->_add_child($adj, resort => 1);
            $adj->head($w);
        }

        $headhead->_add_child($w, resort => 1);
        $w->_add_child($head, resort => 1);

        $head->head($w);
        $w->head($headhead);

        $w->deprel($head->deprel);
        $head->deprel('DET');
    }
    # subordinators
    elsif($pos eq 'CS') {
        my @children = map {$_->postag . "/" . $_->deprel} @{$w->children};
        my @verb = grep {$_->cpostag eq 'V'} @{$w->children};
        return if @verb != 1;

        my $head = $w->head;
        my $verb = $verb[0];

        # Move other dependents of the subordinator to the verb.
        for my $x (@{$w->children}) {
            $w->_delete_child($x);
            $verb->_add_child($x, resort => 1);
            $x->head($verb);
        }

        $head->_delete_child($w);
        $w->_delete_child($verb);

        $head->_add_child($verb, resort => 1);
        $verb->_add_child($w, resort => 1);

        $verb->head($head);
        $w->head($verb);
        # TODO: Deprels
    }
}
