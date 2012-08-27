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

my $corpus = Lingua::CoNLLX->new(file => $ARGV[0]);

for my $s (@{$corpus->sentences}) {
    # TODO: Deprel tagset mapping
    $s->iterate(\&fix_deps);
    $s->iterate(\&posmap);

    print $s, "\n\n";
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

        $w->feats(\@new);
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
        $head->deprel('possr'); # TODO: possr --> DET
    }
    # coordination
    elsif($rel eq 'coord' and $w->form eq 'og') {
        my @children = grep { $_->deprel eq 'conj' } @{$w->children};
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
            $w->_add_child($adj);
            $adj->head($w);
        }

        $headhead->_add_child($w, resort => 1);
        $w->_add_child($head, resort => 1);

        $head->head($w);
        $w->head($headhead);

        $w->deprel($head->deprel);
        $head->deprel('DET');
    }
}
