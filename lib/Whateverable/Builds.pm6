unit package Whateverable::Builds;

my $WORKING-DIRECTORY        = ‘.’; # TODO should be smarter
my $REPO-ORIGIN-RAKUDO       = ‘https://github.com/rakudo/rakudo.git’;
my $REPO-CURRENT-RAKUDO-MOAR = “$WORKING-DIRECTORY/data/rakudo-moar”.IO.absolute;
my $REPO-ORIGIN-MOARVM       = ‘https://github.com/MoarVM/MoarVM.git’;
my $REPO-CURRENT-MOARVM      = “$WORKING-DIRECTORY/data/moarvm”.IO.absolute;
my $BUILDS                   = “$WORKING-DIRECTORY/data/builds”.IO.absolute;

sub ensure-cloned-repos is export {
    # TODO racing
    if $REPO-CURRENT-RAKUDO-MOAR.IO !~~ :d  {
        run <git clone -->, $REPO-ORIGIN-RAKUDO, $REPO-CURRENT-RAKUDO-MOAR;
    }
    if $REPO-CURRENT-MOARVM.IO !~~ :d  {
        run <git clone -->, $REPO-ORIGIN-MOARVM, $REPO-CURRENT-MOARVM;
    }
    mkdir “$BUILDS/rakudo-moar”;
    mkdir “$BUILDS/moarvm”;
    True
}
