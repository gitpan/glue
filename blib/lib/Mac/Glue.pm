package Mac::Glue;

use lib "$ENV{MACPERL}site_perl";
use AutoLoader;
use Carp;
use Data::Dumper;
use Exporter;
use Fcntl;
use Mac::AppleEvents::Simple 0.60 qw(:all);
use Mac::Apps::Launch 1.61;
use Mac::Files;
use Mac::Types;
use MLDBM qw(DB_File Storable);

use strict;
use vars qw($VERSION $AUTOLOAD %AE_PUT %AE_GET
    @EXPORT @EXPORT_OK %EXPORT_TAGS @ISA $GLUEDIR
    $GENPKG $GENSEQ %OPENGLUES %MERGEDCLASSES @OTHEREVENT
    @OTHERCLASS %SPECIALEVENT %SPECIALCLASS);

#=============================================================================#

$VERSION            = '0.20';
@ISA                = qw(Exporter);
@EXPORT             = qw(obj_form);
@EXPORT_OK          = ( @Mac::AppleEvents::EXPORT );
%EXPORT_TAGS        = ( all => [@EXPORT, @EXPORT_OK] );

$GENPKG             = __PACKAGE__;
$GENSEQ             = 0;

# change this if it ever works on other platforms ... Mac OS X?
$ENV{MACGLUEDIR}    ||= "$ENV{MACPERL}site_perl:Mac:Glue:glues:";
$ENV{MACGLUEDIR}    .= ':' unless substr($ENV{MACGLUEDIR}, -1, 1) eq ':';

_open_others();

#=============================================================================#

sub new {
    my($class, $app) = @_;
    my($self, $glue, $db, $app1, $app2);

    # find glue, try a few different names just in case
    ($app1 = $app) =~ tr/ /_/;
    ($app2 = $app) =~ tr/_/ /;
    for (map { "$ENV{MACGLUEDIR}$_" } $app, $app1, $app2) {
        if (-e) {
            $glue = $_;
            last;
        }
    }
    croak "No application glue for '$app' found in '$ENV{MACGLUEDIR}'"
        if !$glue;

    # if not already opened, open and store reference to db
    unless (exists($OPENGLUES{$glue})) {
        tie my %db, 'MLDBM', $glue, O_RDONLY or die $!;
        $OPENGLUES{$glue} = \%db;
    }
    $db = $OPENGLUES{$glue};

    # create new class to put this in
    $class = $GENPKG . "::GLUE" . $GENSEQ++;
    {
        no strict 'refs';
        for (qw(AUTOLOAD _primary _find_event _params _do_obj
            LAUNCH SWITCH REPLY o p)) {
            *{$class . "::$_"} = *{"Mac::Glue::$_"}{CODE};
        }
    }

    $self = {
        _DB => $db, APP => $db->{APP}, SWITCH => 0,
        GLUEFILE => $app, GLUE => bless({}, 'Mac::Glue'),
        CLASS => _merge_classes($db)
    };

    bless($self, $class);
}

#=============================================================================#

sub _primary {
    my($self, $e, @args) = @_;
    my($evt, $rep, %done);

    my($class, $event, $reply, $params) = @{$e}{qw(class event reply params)};

    my @req = grep {$params->{$_}[2] == 1} keys %$params;

    $evt = build_event($class, $event, $self->{APP});

    my $dobj = shift @args unless ref($args[0]) eq 'HASH';
    if (defined($dobj)) {
        croak "Direct object parameter not present"
            unless exists($params->{keyDirectObject()});
        $self->_params($evt, $params->{keyDirectObject()}, $dobj);
        $done{keyDirectObject()}++;
    }

    my $hash = shift @args if ref($args[0]) eq 'HASH';
    if ($hash) {
        foreach my $p (keys %$hash) {
            next if $p =~ /^_(?!dobj)/;
            my $pp = $p eq '_dobj' ? keyDirectObject() : $p;
            croak "$p parameter not available"
                unless exists($params->{$pp});
            $self->_params($evt, $params->{$pp}, $hash->{$p});
            $done{$pp}++;
        }
    }

    if ($^W) {
        foreach (@req) {
            # croak?
#            carp "'$_' is required parameter" unless exists $done{$_};
        }
    }

    if (1) {  # switch to 0 for testing
        local $Mac::AppleEvents::Simple::SWITCH =
            $hash->{'_switch'}
                ? $hash->{'_switch'}
                : $self->{SWITCH};

        # we'll wait if _reply not set and _timeout is set
        if (!exists $hash->{'_reply'} && exists $hash->{'_timeout'}) {
            $self->{REPLY} = 1;
        }

        my $mode =
            ((exists $hash->{'_reply'}      # check event setting
                ? $hash->{'_reply'}
                : exists $self->{REPLY}     # check global setting
                    ? $self->{REPLY}
                    : $reply->[0] ne 'null' # check AETE setting
            )
                ? kAEWaitReply
                : kAENoReply)

                | (exists $hash->{'_mode'}
                    ? $hash->{'_mode'}
                    : exists $self->{MODE}
                        ? $self->{MODE}
                        : (kAECanInteract | kAECanSwitchLayer));

        my $priority =
            exists $hash->{'_priority'}
                ? $hash->{'_priority'}
                : exists $self->{PRIORITY}
                    ? $self->{PRIORITY}
                    : kAENormalPriority;

        my $timeout = 60 *
            (exists $hash->{'_timeout'}
                ? $hash->{'_timeout'}
                : exists $self->{TIMEOUT}
                    ? $self->{TIMEOUT}
                    : 2**18                 # some big number
            );

        $evt->send_event($mode, $priority, $timeout);
    }
    return $evt;
}

#=============================================================================#

sub _params {
    my($self, $evt, $p, $data) = @_;
    my($key, $type) = @{$p}[0..1];

    # AE lists
    if (ref($data) eq 'ARRAY') {
        my($list, $count) = (AECreateList('', 0), 0);

        foreach (@{$data}) {
            my($d, $t) = exists($AE_PUT{$type}) ? &{$AE_PUT{$type}}($_, $evt, $p) : $_;
            $type = $t || $type;
            if (ref($d) eq 'AEDesc') {
                AEPutDesc($list, ++$count, $d);
                AEDisposeDesc($d);
            } elsif (ref($d) eq 'AEObjDesc') {
                AEPutDesc($list, ++$count, $d->{DESC});
            } else {
                AEPut($list, ++$count, $type, $d);
            }
        }
        AEPutParamDesc($evt->{EVT}, $key, $list);
        AEDisposeDesc($list);

    # AE objects
    } elsif (ref($data) eq 'AEObjDesc') {
        AEPutParamDesc($evt->{EVT}, $key, $data->{DESC});

    # AE descriptors
    } elsif (ref($data) eq 'AEDesc') {
        AEPutParamDesc($evt->{EVT}, $key, $data);

    # simple descriptors
    } else {
        $type = $type eq '****' ?
            $data =~ /^-?\d+$/ ? 'shor' : 'TEXT' : $type;
        my $d = exists($AE_PUT{$type}) ? &{$AE_PUT{$type}}($data, $evt, $p) : $data;
        if (ref($d) eq 'AEDesc') {
            AEPutParamDesc($evt->{EVT}, $key, $d);
            AEDisposeDesc($d);
        } else {
            AEPutParam($evt->{EVT}, $key, $type, $d);
        }            
    }
}

#=============================================================================#

sub _do_obj {
    my($self, $data, $class, $from, $lclass, $list, $obj, $form, $form2, $form3) = @_;
    croak "Class $class does not exist.\n" if (!exists($self->{CLASS}{$class}));

    if ($class eq 'property' && $lclass) {
        $form = 'prop';
        if (exists($self->{CLASS}{$lclass}{properties}{$data})) {
            $data = $self->{CLASS}{$lclass}{properties}{$data}[0];
        } elsif (exists($self->{CLASS}{$data})) {
            $data = $self->{CLASS}{$data}{id};
        } elsif (exists($self->{CLASS}{application}{properties}{$data})) {
            $data = $self->{CLASS}{application}{properties}{$data}[0];
        } else {
            print "$lclass, $self->{CLASS}{item}{properties}\n";
            croak "Can't find property '$data'.\n";
        }
    } elsif (ref($data) eq 'AEObjDescForm') {
        $form = $$data[0];
        $data = $$data[1];
    } elsif ($data =~ /^-?\d+$/) {
        $form = 'indx';
    } else {
        $form = 'name';
    }

    if ($form eq 'name') {
        $form2 = $form3 = 'TEXT';
    } elsif ($form eq 'indx') {
        $form2 = $form3 = 'shor';
    } elsif ($form eq 'prop') {
        $form2 = $form3 = 'type';
    } else {
        $form2 = $form3 = $form;
    }

    $class = $self->{CLASS}{$class};
    $list = AECreateList('', 1);

    AEPutParam($list, 'want', 'type', $class->{id});
    if ($from) {
        AEPutParamDesc($list, 'from', $from);
        AEDisposeDesc($from);
    } else {
        AEPutParam($list, 'from', 'null', '');
    }
    AEPutParam($list, 'form', 'enum', $form);

    my $d = exists($AE_PUT{$form3}) ? &{$AE_PUT{$form3}}($data) : $data;
    if (ref($d) eq 'AEDesc') {
        AEPutParamDesc($list, 'seld', $d);
        AEDisposeDesc($d);
    } else {
        AEPutParam($list, 'seld', $form2, $d);
    }            

    $obj = AECoerceDesc($list, 'obj ');
    AEDisposeDesc($list);
    return($obj);
}

#=============================================================================#

sub _open_others {
    my @others;
    foreach my $dir (map { "$ENV{MACGLUEDIR}$_" } qw[dialects additions]) {
        local *DIR;
        opendir DIR, $dir or die $!;
        chdir $dir or die $!;

        foreach (readdir DIR) {
            # if anything is in these directories other
            # that Icon files, POD files, and glue files,
            # you will die, and it is not my fault -- CN
            # :)

            next if /\.pod$/;
            next if $_ eq "Icon\n";
            tie my %db, 'MLDBM', $_, O_RDONLY or die $!;
            push @OTHEREVENT, $db{EVENT};
            push @OTHERCLASS, $db{CLASS};
        }
    }
}

#=============================================================================#

sub _find_event {
    my($self, $name) = @_;
    my $event;

    for (@OTHEREVENT, $self->{_DB}{EVENT}) {
        if (exists $_->{$name}) {
            $event = $_->{$name};
            last;
        }
    }

    $event ||= $SPECIALEVENT{$name} if exists $SPECIALEVENT{$name};

    return $event;
}

#=============================================================================#

sub _merge_classes {
    my $db = shift;
    if (exists $MERGEDCLASSES{ $db->{APP} }) {
        return $MERGEDCLASSES{ $db->{APP} };
    } else {
        my($class, @classes) = ($db->{CLASS}, @OTHERCLASS);
        foreach my $tempc (@classes) {
            foreach my $c (keys %$tempc) {
                if (exists($$class{$c})) {
                    foreach my $p (keys %{$tempc->{properties}}) {
                        if (!exists($class->{$c}{properties}{$p})) {
                            $class->{$c}{properties}{$p} = $tempc->{$c}{properties}{$p};
                        }
                    }
                } else {
                    $class->{$c} = $tempc->{$c};
                }
            }
        }
        return $MERGEDCLASSES{ $db->{APP} } = $class;
    }
}

#=============================================================================#

# create an AE object
sub o {
    my($self, @data, $obj) = @_;
#    croak "Must be an even number of elements in parameter list"
#        if @data % 2;
    @data = reverse @data;
    $obj = '';

    for (my $i = 0; $i <= $#data; $i++) {
        my $v = $data[$i];
        if (ref($v) eq 'AEObjDesc') {
            $obj = $v->{DESC};
        } else {
            $i++;
            my $k = $data[$i];
            $obj = $self->_do_obj($v, $k, $obj, $data[$i-2]);
        }
    }

    return bless {DESC=>$obj}, 'AEObjDesc';
}


#=============================================================================#

# launch the app (done automatically when an event is called if not running)
sub LAUNCH {
    my($self, $location) = @_;
    if (defined $location) {
        LaunchSpecs($location);
    } else {
        LaunchApps($self->{APP});
    }
}

#=============================================================================#

# catch all
sub AUTOLOAD {
    my $self    = $_[0];
    my @args    = @_[1 .. -1];
    (my $name = $AUTOLOAD) =~ s/^.*://;

    for ($name) {
        if (/^DESTROY$/) {
          goto &AutoLoader::AUTOLOAD;
        } elsif (/^(REPLY|SWITCH|MODE|PRIORITY|TIMEOUT)$/) {
            no strict 'refs';
            *{$AUTOLOAD} =
                sub { $_[0]->{$name} = $_[1] if $_[1]; $_[0]->{$name} };
            goto &$AUTOLOAD;
        }
    }

    my $event = $self->_find_event($name)
        or die "No event '$name' available from glue for '$self->{GLUE}'";

    # create new sub, only do AUTOLOAD for it once!
    no strict 'refs';
    *{$AUTOLOAD} = sub { $_[0]->_primary($event, @_[1 .. $#_]) };
    goto &$AUTOLOAD;
}

#=============================================================================#

# shortcut to create a property
sub p {return shift->o('property', @_)}

# special function to help control object creation
sub obj_form ($$) {return bless [@_], 'AEObjDescForm'}

sub AEObjDesc::DESTROY {AEDisposeDesc(shift()->{DESC})}

#=============================================================================#

BEGIN {
    %AE_PUT = (
        'alis' => sub {NewAliasMinimal(shift)->get},
        'shor' => sub {MacPack('shor', shift)},
        'long' => sub {MacPack('long', shift)},
        'bool' => sub {MacPack('bool', shift)},
        'TEXT' => sub {MacPack('TEXT', shift)},
        'fss ' => sub {MacPack('fss ', shift)},
#        'itxt' => sub {'    '.MacPack('TEXT', shift)},
        '****' => sub {
            my $type = ($_[0] =~ /^-?\d+$/ ? 'shor' : 'TEXT');
            return(&{$AE_PUT{$type}}($_[0]), $type);
        },
    );

    %AE_GET = (
        'alis' => sub {ResolveAlias(shift->data)},
    );

    %SPECIALEVENT = (
        'set'    => {'class' => 'core', 'event' => 'setd',
                    'reply' => ['****', 0, 0, 0], 'params' => {
                        '----' => [keyDirectObject(), 'obj ', 1, 0, 0, 1],
                        'to' => ['data', '****', 1, 0, 0],
                    }},
        'get'    => {'class' => 'core', 'event' => 'getd',
                    'reply' => ['****', 1, 0, 0], 'params' => {
                        '----' => [keyDirectObject(), 'obj ', 1, 0, 0, 0],
                        'as' => ['rtyp', 'type', 0, 1, 0],
                    }},
    );

    %SPECIALCLASS = (
    
    );

}

#=============================================================================#

1;

__END__

=head1 NAME

Mac::App::Glue - Control Mac apps with a simple syntax

=head1 SYNOPSIS

    use Mac::Glue::SomeApp;
    my $obj = new Mac::Glue::SomeApp;
    $obj->some_event('direct object', {param1=>'data', param2=>'data'});

=head1 DESCRIPTION

C<Mac::Glue> is a framework for controlling scriptable Mac applications,
with a vocabulary similar to AppleScript, but in Perl syntax.

This module provides the guts for modules in the C<Mac::Glue> namespace.
These modules are created with the C<glue_me.dp> droplet.

=head2 Constructing the Object

To use a given application glue, first, an object is constructed with C<new>:

    use Mac::Glue::Finder;
    my $f = new Mac::Glue::Finder;

=head2 Calling Events

Then the object, in this case C<$f>, is used for calling that application's
events.  Parameters are passed as follows:

=over 4

=item The event's direct object parameter, if there is one, is passed as
the first parameter of the event.

    $f->open('HD:file');

=item Other parameters are passed in an anonymous hash, as the second
parameter to the event.  If there is no direct object, then it is passed
as the first parameter.  The direct object may be passed in the hash
instead of separately, with the keyword C<_dobj>.

    $f->open('HD:file', {using=>'HD:my app'});
    $f->open({_dobj=>'HD:file', using=>'HD:my app'});

=item Simple data is passed as a simple scalar.

    $f->open('HD:file');

=item Lists are passed as anonymous arrays.

    $f->open(['HD:file', 'HD:file2']);

=item Apple Event objects are created with C<$f-E<gt>o()> and then
passed as simple scalars.  The object data (below, 'file' and 'HD')
is considered to be of type C<indx> if it is an integer, and type
C<TEXT> if it is not.  This can be overriden with the C<obj_form>
function, described below.

    my $obj = $f->o(item=>'file', disk=>'HD');
    $f->open($obj);

=back

C<Mac::Glue> will do its best to try to convert the given data into
the appropriate type.  If it fails, then C<Mac::Glue> needs to be modified
to make it work.  Mail me about it.

For example, in the above code C<$f-E<gt>open('HD:file')>, the module
knows that C<open> takes an alias, and converts the data appropriately.

The glue apps do not have any real subroutines created, they are all 
accessed dynamically via AUTOLOAD.  So if you need to, in your glue
module, short-circuit the functions in C<Mac::Glue>, you can do so 
by just creating a real subroutine.  For example, the Finder has
two C<open> events.  So we short-circuit both of them.

First, we rename one of the events to C<open2>.  Then we make
an C<open> subroutine, and redirect the parameters to whichever
event we want called.

    sub open {
        my($self, @args) = @_;
        # if $arg[0] is an AE object
        if (ref($args[0]) eq 'AEObjDesc') {
            $self->_primary('open2', @args);
        # if the direct object is in the anon hash, and is an AE object
        } elsif ($args[0] eq 'HASH' && exists($args[0]->{_dobj})
            && ref($args[0]->{_dobj}) eq 'AEObjDesc') {
            $self->_primary('open2', @args);
        } else {
            $self->_primary('open', @args);
        }
    }

=head2 Returning Events

Your event call will only wait for a reply, by default, if the
given event's first reply parameter is not C<null> in the module:

    'reply' => ['null', 0, 0, 0],   # will not return reply
    'reply' => ['long', 0, 0, 0],   # will return reply

It is up to the target application as to whether or not to actually reply,
of course.

You can override the defauly behavior by adding the C<_reply> parameter
to your event hash.

    $f->event({_reply=>1});  # wait for reply
    $f->event({_reply=>0});  # don't wait for reply

Regardless of whether or not your event waits for a reply, your event call
will return a C<Mac::AppleEvents::Simple> object containing information
about that call.  See C<Mac::AppleEvents::Simple> for more information.
You may also need to import functions from C<Mac::AppleEvents> to
extract information from the event or the reply.

Just as with all C<Mac::AppleEvents::Simple> events, if the reply
contains an C<errn> or C<errs> parameter, and your program is checking
for warnings (with the C<-w> switch), then the errors will trigger
warnings.


=head2 Other Stuff

When an event is called, the application will automatically be launched
if it is not already running,
using the app's ID embedded in the glue module.  To override which app
is used (say, because you have two versions), launch another version
first, either manually, or with the C<LaunchSpecs> function in the
C<Mac::Apps::Launch> module.

You can also launch the app before calling your first event with the
C<_launch> method.

    $f->_launch();

When an event is called, the target app is switched to the frontmost app,
unless you override it with the C<_switch> method, or by passing the
C<_switch> parameter in the event.

    $f->_switch(0);  # don't switch
    $f->event({_switch=>0});  # don't switch


=head1 EXPORT

Everything in C<Mac::AppleEvents> is exported by C<Mac::Glue>,
which is never meant to be used directly.  From the glue modules
themselves, only one function is exported by default, C<obj_form>.

This function overrides the default data type to be used in a given
object.  Integers are assumed to be of type C<indx>, otherwise it is
assumed to be type C<TEXT>.  This is overriden as such:

    $obj = $f->o(window=>123);                  # 123 is of type indx
    $obj = $f->o(window=>obj_form(long=>123));  # 123 is of type long

All else that is exported by C<Mac::AppleEvents>/C<Mac::Glue> is available
from the C<:all> export tag:

    use Mac::Glue::SomeModule qw(:all);

=head1 HISTORY

=over 4

=item v0.09, 13 October 1998

Added ability to use properties.  These are called with the C<p> method:

    $obj->get($obj->p('label_index', item=>'HD'));

which is equivalent to:

    $obj->get($obj->o(property=>'label_index', item=>'HD'));

=item v0.08, 10 October 1998

Unreleased.

Significant cleanup of module, in large part unfinished changes from
last version.

No longer doing error checking for whether lists are allowed or objects
are allowed, because these are sometimes wrong or undetectable.  Also,
will not raise exception on a missing required parameter, but will warn
if C<-w> is on.

C<obj_form> is exported from the glue modules, and all of the functions
and constant from C<Mac::AppleEvents> can be imported from a glue module
with the C<:all> tag:

    use Mac::Glue::SomeApp qw(:all);

=item v0.07, 30 September 1998

More documentation and bugfixes.  Having serious problems with
C<AEObjDesc::DESTROY>.

=item v0.06, 29 September 1998

Whole bunches of changes.  Note that glues made under 0.05 no longer work.

=back


=head1 AUTHOR

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/

Copyright (c) 1999 Chris Nandor.  All rights reserved.  This program is
free software; you can redistribute it and/or modify it under the terms
of the Artistic License, distributed with Perl.


=head1 THANKS

Matthias Neeracher E<lt>neeri@iis.ee.ethz.chE<gt>,
David Schooley E<lt>dcschooley@mediaone.netE<gt>,
John W Baxter E<lt>jwblist@olympus.netE<gt>,
Eric Dobbs E<lt>dobbs@visionlink.orgE<gt>,
Josh Gemmell E<lt>joshg@ola.bc.caE<gt>,
Nathaniel Irons E<lt>irons@espresso.hampshire.eduE<gt>,
Dave Johnson E<lt>dave_johnson@ieee.orgE<gt>,
Jefferson R. Lowrey E<lt>lowrey@postoffice.sells.comE<gt>,
Mat Marcus E<lt>mmarcus@adobe.comE<gt>,
Vincent Nonnenmacher E<lt>dpi@pobox.oleane.comE<gt>,
Ramesh R. E<lt>sram0mp@radon.comm.mot.comE<gt>,
Stephan Somogyi E<lt>somogyi@gyroscope.netE<gt>.


=head1 SEE ALSO

Mac::AppleEvents, Mac::AppleEvents::Simple, macperlcat, Inside Macintosh: 
Interapplication Communication.

=cut
