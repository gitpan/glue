package Mac::AppleEvents::Simple;
require 5.004;
use Carp;
use Mac::AppleEvents;
use Mac::Processes;
use Mac::Apps::Launch 1.70;
use Mac::Files;
use Mac::Types;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION $SWITCH
    %AE_GET %DESCS $DESCCOUNT $WARN $DEBUG);
use strict;
use Exporter;
use Carp;

#-----------------------------------------------------------------

@ISA = qw(Exporter Mac::AppleEvents);
@EXPORT = qw(do_event build_event);
@EXPORT_OK = @Mac::AppleEvents::EXPORT;
%EXPORT_TAGS = (all => [@EXPORT, @EXPORT_OK]);
$VERSION = '0.71';
$DEBUG  ||= 0;
$SWITCH ||= 0;
$WARN   ||= 0;

#-----------------------------------------------------------------
# Main public methods and functions
#-----------------------------------------------------------------

sub do_event {
    my $self = bless _construct(@_), __PACKAGE__;
    $self->_build_event and return $self->_warn;
    $self->_send_event and return $self->_warn;
    $self->_sending and return $self->_warn;
    $self;
}

#-----------------------------------------------------------------

sub build_event {
    my $self = bless _construct(@_), __PACKAGE__;
    $self->_build_event and return $self->_warn;
    $self->_print_desc('EVT') and return $self->_warn;
    $self;
}

#-----------------------------------------------------------------

sub send_event {
    my $self = shift;
    $self->_send_event(@_) and return $self->_warn;
    $self->_sending and return $self->_warn;
    $self;
}

#-----------------------------------------------------------------

sub data {
    my($self, $key) = @_;
    my($d, $desc, $num, @ret);

    $d = ref $self eq __PACKAGE__ ? $self->{REP} : $self;
    return unless ref $d eq 'AEDesc';
    return unless
        defined($desc = AEGetParamDesc($d, $key || keyDirectObject));

    # special-case typeAERecord here, too?
    if ($num = AECountItems($desc)) {
        for (1 .. $num) {
            my $d = AEGetNthDesc($desc, $_);
            push @ret, $d;
        }
        return wantarray ? @ret : $ret[0];
    } else {
        return $desc;
    }
}

#-----------------------------------------------------------------

sub get {
    my($self, $key) = @_;
    my($d, $desc, $num);

    $d = ref $self eq __PACKAGE__ ? $self->{REP} : $self;
    return unless ref $d eq 'AEDesc';
    return unless
        defined($desc = AEGetParamDesc($d, $key || keyDirectObject));

    if ($num = AECountItems($desc)) {

        if ($desc->type eq typeAEList) {
            my @ret;
            for (1..$num) {
                push @ret, _getdata(AEGetNthDesc($desc, $_));
            }
            # if scalar context, return ref instead?
            return wantarray ? @ret : $ret[0];

        } elsif ($desc->type eq typeAERecord) {
            my %ret;
            for (1..$num) {
                my @d = AEGetNthDesc($desc, $_);
                $ret{$d[1]} = _getdata($d[0]);
            }
            # if scalar context, return ref instead?
            return %ret;
        }

    } else {
        return _getdata($desc);
    }
}

#-----------------------------------------------------------------
# Private methods
#-----------------------------------------------------------------

sub _getdata {
    my $desc = shift;
    my $type = $desc->type;

    my($ret, $keep) = exists($AE_GET{$type})
        ? &{$AE_GET{$type}}($desc)
        : $desc->get;

    AEDisposeDesc $desc unless $keep;
    return $ret;
}

#-----------------------------------------------------------------

sub _sending {
    my $self = shift;
    $self->_print_desc('EVT');
    $self->_print_desc('REP');
    $self->_event_error;
}

#-----------------------------------------------------------------

sub _construct {
    my $self = {};
    $self->{CLASS} = shift or croak 'Not enough parameters in AE build';
    $self->{EVNT} = shift or croak 'Not enough parameters in AE build';
    $self->{APP} = shift or croak 'Not enough parameters in AE build';
    $self->{DESC} = shift || '';
    $self->{PARAMS} = [@_];
    $self;
}

#-----------------------------------------------------------------

sub _print_desc {
    my $self = shift;
    my %what = (EVT => 'EVENT', REP => 'REPLY');
    $self->{$what{$_[0]}} = AEPrint $self->{$_[0]};
}

#-----------------------------------------------------------------

sub _build_event {
    my $self = shift;
    $self->{EVT} = AEBuildAppleEvent(
        $self->{CLASS}, $self->{EVNT}, typeApplSignature,
        $self->{APP}, kAutoGenerateReturnID, kAnyTransactionID,
        $self->{DESC}, @{$self->{PARAMS}}
    );
    $self->{ERROR} = $^E;
    $self->{ERRNO} = 0+$^E;
}

#-----------------------------------------------------------------

sub _send_event {
    my $self = $_[0];

    LaunchApps($self->{APP}, 0) unless IsRunning($self->{APP});
    SetFront($self->{APP}) if $SWITCH;

    $self->{R} = defined $_[1] ? $_[1] : $self->{GETREPLY} || kAEWaitReply;
    $self->{P} = defined $_[2] ? $_[2] : $self->{PRIORITY} || kAENormalPriority;
    $self->{T} = defined $_[3] ? $_[3] : $self->{TIMEOUT}  || kNoTimeOut;

    $self->{REP} = AESend(@{$self}{'EVT', 'R', 'P', 'T'});
    $self->{ERROR} = $^E;
    $self->{ERRNO} = 0+$^E;
}

#-----------------------------------------------------------------

sub _event_error {
    my($self) = @_;
    my($event, $error);

    delete $self->{ERRNO};
    $event = $self->{REP};
    return unless $event;

    if (my $errn = AEGetParamDesc($event, keyErrorNumber)) {
        $self->{ERRNO} = $errn->get;
        AEDisposeDesc($errn);
    }

    if (my $errs = AEGetParamDesc($event, keyErrorString)) {
        $self->{ERROR} = $errs->get;
        AEDisposeDesc($errs);
    }

    if (exists $self->{ERRNO}) {
        $^E = $self->{ERRNO};
        $self->{ERROR} ||= $^E;
    }

    $self;
}

#-----------------------------------------------------------------

sub _warn {
    my $self = $_[0];
    if ($WARN) {
        if ($self->{ERROR}) {
            carp $self->{ERROR};
        } elsif ($self->{ERRNO}) {
            $self->{ERROR} = local $^E = $self->{ERRNO};
            carp "Error $self->{ERRNO}: $^E";
        }
    }
    $self;
}

#-----------------------------------------------------------------

DESTROY {
    my $self = shift;
    local $^E;  # save $^E
    AEDisposeDesc $self->{EVT} if $self->{EVT};
    AEDisposeDesc $self->{REP} if $self->{REP};
}

#-----------------------------------------------------------------

END {
    foreach my $desc (keys %DESCS) {
        print "Destroying $desc\n" if $DEBUG;
        if ($desc) {
            eval { print "\t", AEPrint($DESCS{$desc}), "\n" } if $DEBUG;
            AEDisposeDesc $DESCS{$desc} or die "Can't dispose $desc: $!";
        }
    }
}

#-----------------------------------------------------------------

BEGIN {
    %AE_GET = (

        typeAlias()             => sub {
            my $alis = $_[0]->data;
            return ResolveAlias($alis) or die "Can't resolve alias: $^E";
        },

        typeObjectSpecifier()   => sub {
            $DESCS{ $_[0] } = $_[0];
            return($_[0], 1);
        },

        typeAEList()            => sub {
            my $list = $_[0];
            my @data;
            for (1 .. AECountItems($list)) {
                my $d = AEGetNthDesc($list, $_) or die "Can't get desc: $^E";
                push @data, _getdata($d);
            }
            return \@data;
        },

        typeAERecord()          => sub {
            my $reco = $_[0];
            my %data;
            for (1 .. AECountItems($reco)) {
                my @d = AEGetNthDesc($reco, $_) or die "Can't get desc: $^E";
                $data{$d[1]} = _getdata($d[0]);
            }
            return \%data;
        },

        STXT => sub { _get_coerce($_[0], typeChar) },
        itxt => sub { _get_coerce($_[0], typeChar) },
        tTXT => sub { _get_coerce($_[0], typeChar) },

        QDpt                    => sub {
            my $string = $_[0]->data->get;
            return [reverse unpack "s4s4", $string]
        
        },

    );
}

sub _get_coerce { AECoerceDesc(@_)->get }

#=============================================================================#

1;

__END__

=head1 NAME

Mac::AppleEvents::Simple - MacPerl module to do Apple Events more simply

=head1 SYNOPSIS

    #!perl -w
    use Mac::AppleEvents::Simple;
    use Mac::Files;  # for NewAliasMinimal
    $alias = NewAliasMinimal(scalar MacPerl::Volumes);
    do_event(qw/aevt odoc MACS/, "'----':alis(\@\@)", $alias);

    # [...]
    use Mac::AppleEvents;  # for kAENoReply
    $evt = build_event(qw/aevt odoc MACS/, "'----':alis(\@\@)", $alias);
    die "There was a problem: $^E" if $^E;
    $evt->send_event(kAENoReply);
    die "There was a problem: $^E" if $^E;
    

=head1 DESCRIPTION

This is just a simple way to do Apple Events.  The example above was 
previously done as:

    #!perl -w
    use Mac::AppleEvents;
    use Mac::Files;
    $alias = NewAliasMinimal(scalar MacPerl::Volumes);
    $evt = AEBuildAppleEvent(qw/aevt odoc sign MACS 0 0/,
        "'----':alis(\@\@)", $alias) or die $^E;
    $rep = AESend($evt, kAEWaitReply) or die $^E;
    AEDisposeDesc($rep);
    AEDisposeDesc($evt);

The building, sending, and disposing is done automatically.  The function 
returns an object containing the parameters, including the C<AEPrint> 
results of C<AEBuildAppleEvent> C<($event-E<gt>{EVENT})> and C<AESend>
C<($event-E<gt>{REPLY})>.

The raw AEDesc forms are in C<($event-E<gt>{EVT})> and C<($event-E<gt>{REP})>.
So if I also C<use>'d the Mac::AppleEvents module (or got the symbols via
C<use Mac::AppleEvents::Simple ':all'>), I could extract the direct
object from the reply like this:

    $dobj = AEPrint(AEGetParamDesc($event->{REP}, keyDirectObject));

An easier way to get the direct object data, though, is with the C<get>
method, described below.

The sending of the event uses as its defaults (C<kAEWaitReply>,
C<kAENormalPriority>, C<kNoTimeout>).  To use different parameters, use
C<build_event> with C<send_event>.

Setting C<$Mac::AppleEvents::Simple::SWITCH = 1> forces the target app to
go to the front on sending an event to it.

Sending an event with C<send_event> or C<do_event> will check for errors
automatically, and if there is an error and C<$Mac::AppleEvents::Simple::WARN>
is true, a warning will be sent to C<STDERR>.  You can also check C<$^E>
after each call, or check the values of C<$event-E<gt>{ERRNO}> and
C<$event-E<gt>{ERROR}>.

If the event reply itself contains a C<errn> or C<errs> parameter, these
will also be placed in C<$event-E<gt>{ERRNO}> and C<$event-E<gt>{ERROR}>
and C<$^E> as appropriate.

You may decide to roll your own error catching system, too.  In this
example, the error is returned in the direct object parameter.

    my $event = do_event( ... );
    die $^E if $^E;  # catch execution errors
    my_warn_for_this_app($event);  # catch AE reply errors

    sub my_warn_for_this_app {
        my $event = shift;
        my $error = AEGetParamDesc($event->{REP}, keyDirectObject);
        if ($error) {
            my $err = $error->get;
            if ($err =~ /^-\d+$/ && $^W) {
                warn "Application error: $err";
            }
            AEDisposeDesc($error);
        }
    }


=head1 REQUIREMENTS

MacPerl 5.2.0r4 or better, and Mac::Apps::Launch 1.70.


=head1 FUNCTIONS

=over 4

=item [$EVENT =] do_event(CLASSID, EVENTID, APPID, FORMAT, PARAMETERS ...)

The first three parameters are required.  The FORMAT and PARAMETERS
are documented elsewhere; see L<Mac::AppleEvents> and L<macperlcat>.


=item $EVENT = build_event(CLASSID, EVENTID, APPID, FORMAT, PARAMETERS ...)

This is for delayed execution of the event, or to build an event that will be 
sent specially with C<send_event>.  Build it with C<build_event>, and then 
send it with C<send_event> method.


=item $EVENT->send_event([GETREPLY, PRIORITY, TIMEOUT]);

    ***NOTE***
    Previously, you could set $object->{REPLY}.  But REPLY was already
    taken.  Whoops.  You now need to set $object->{GETREPLY}.

For sending events differently than the defaults, which are C<kAEWaitReply>,
C<kAENormalPriority>, and C<kNoTimeout>, or for re-sending an event.  The
parameters  are sticky for a given event, so:

    $evt->send_event(kAENoReply);
    $evt->send_event;  # kAENoReply is still used


=item $EVENT->data([KEY])

=item $EVENT->get([KEY])

=item data(DESC[, KEY])

=item get(DESC[, KEY])

Similar to C<get> and C<data> from the Mac::AppleEvents module.
Get data from a Mac::AppleEvents::Simple object for a given key
(C<keyDirectObject> is the default).  Can also be called as a function,
where an AEDesc object is passed as the first parameter.

For C<data>, if the descriptor in KEY is an AE list, then a list
of the descriptors in the list will be returned.  In scalar context,
only the first element will be returned.

On the other hand, C<get> will return a nested data structure,
where all nested AE lists will be converted to perl array references,
and all nested AE records will be converted to perl hash references.
In scalar context, only the first element of the base list will be
returned for AE lists.

Also, C<get> will attempt to convert other data into a more usable form
(such as resolving aliases into paths).

=back

=head1 EXPORT

Exports functions C<do_event>, C<build_event>.

=head1 HISTORY

=over 4

=item v0.71, Tuesday, June 8, 1999

Added C<$DEBUG> global.  Will be used more.

Added some coercions so certain types will be returned as typeChar
from the C<get> method.

=item v0.70, Friday, June 4, 1999

Removed deprecated C<ae_send> function.  Use C<send_event> instead.

Removed deprecated C<get_text> function.  Not needed anymore, use C<get>
method instead.

Cleaned up stuff.

Improved error handling.  Will return on first error.  See docs above
for more information.

Made C<$Mac::AppleEvents::Simple::SWITCH> C<0> by default instead of C<1>.

Added global <%DESCS> to save AEDescs for disposal later.

=item v0.65, May 30, 1999

No longer return entire desc from C<get> if direct object not supplied.

Error number put in C<$^E> if supplied.

Added a bunch of stuff to C<%AE_GET>.

C<get> method now automatically unpacks nested AE records and AE lists into
perl hash and array references.

=item v0.61, May 1, 1999

Made default timeout C<kNoTimeOut>.

Changed use of C<REPLY> for parameter to C<AESend> to C<GETREPLY>.
C<REPLY> was already in use, D'oh!

=item v0.60, January 28, 1999

Added C<get> and C<data> methods.

=item v0.52, September 30, 1998

Re-upload, sigh.

=item v0.51, September 29, 1998

Fixed problems accepting parameters in C<send_event>.   Sped up
switching routine significantly.

=item v0.50, September 16, 1998

Only C<LaunchApps> when sending event now if $SWITCH is nonzero or
app is not already running.

Added warnings for event errors if present and if C<$^W> is nonzero.
Only works if event errors use standard keywords C<errs> or C<errn>.

=item v0.10, June 2, 1998

Changed C<new> to C<build_event>, and C<ae_send> to C<send_event>.

Made default C<AESend> parameters overridable via C<send_event>.

=item v0.03, June 1, 1998

Added C<$SWITCH> global var to override making target app go to front.

=item v0.02, May 19, 1998

Here goes ...

=back

=head1 AUTHOR

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/

Copyright (c) 1999 Chris Nandor.  All rights reserved.  This program is
free software; you can redistribute it and/or modify it under the terms
of the Artistic License, distributed with Perl.

=head1 SEE ALSO

Mac::AppleEvents, Mac::OSA, Mac::OSA::Simple, macperlcat.

=cut

=head1 VERSION

v0.70, Friday, June 4, 1999
