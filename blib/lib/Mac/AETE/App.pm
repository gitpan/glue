# 
# # Copyright (c) 1999 David Schooley.  All rights reserved.  This program is 
# free software; you can redistribute it and/or modify it under the same 
# terms as Perl itself.

########################################################################
#                                                                      #
#   Do the following:                                                  #
#    See if the app is running, if so, send the GetAETE event to it.   #
#    If it is not running, see if it has a sisz resource,              #
#      if so, launch it and send the GetAETE event to it.              #
#      if not, read in the aete directly.                              #
#                                                                      #
########################################################################

package App;

=head1 NAME

App - reads the Macintosh Apple event dictionary from an application.


=head1 SYNOPSIS

     use Mac::AETE::App;
     use Mac::AETE::Format::Dictionary;

     $app = App->new("My Application");
     $formatter = Dictionary->new;
     $app->set_format($formatter);
     $app->read;
     $app->write;


=head1 DESCRIPTION

The App module simplifies reading the Apple event dictionary from an application. 
It will launch the application if necessary to obtain the dictionary. 

=head2 Methods

=over 10

=item new

Example: ($name is the name of the application.)

     use Mac::AETE::App;
     use Mac::AETE::Format::Dictionary;

     $app = App->new($aete_handle, $name);

=item read

(Inherited from Mac::AETE::Parser.)

Reads the data contained in the AETE resource or handle. Example:
     
     $app->read;

=item set_format

(Inherited from Mac::AETE::Parser.)

Sets the output formatter used during by the 'write' subroutine. Example:

     $formatter = Dictionary->new;
     $app->set_format($formatter);
     

=item copy

(Inherited from Mac::AETE::Parser.)

Copies all suites from one Parser object into another. Example:
     
     $aete2 = Parser->new($aete_handle2, $another_name);
     $app->copy($aete2);
     
copies the suites from $aete2 into $aete.

=item merge

(Inherited from Mac::AETE::Parser.)

Merges suites from one Parser object into another. Only the suites that exist in
both objects will be replaced. Example:

     $aete3 = Parser->new($aete_handle2, $another_name);
     $app->merge($aete3);

=item write

(Inherited from Mac::AETE::Parser.)

Prints the contents of the AETE or AEUT resource using the current formatter.

     $app->write;

=back

=head1 INHERITANCE

Inherits from Mac::AETE::Parser.

=head1 AUTHOR

David Schooley <F<dcschooley@mediaone.net>>

=cut


use strict;
use Mac::AETE::Parser;
use Mac::AppleEvents;
use Mac::Files;
use Mac::Memory;
use Mac::Processes;
use Mac::Resources;
use File::Basename;

use Carp;

@App::ISA = qw (Parser);

sub new {
    my ($type, $target) = @_;
    my $self = {};
    my $aete_handle;
    
    my ($name, $running) = &get_app_status_and_launch($target);

    $self->{_target} = $name;

    if ($running) {
        $aete_handle = get_aete_via_event($target);
        croak("The application is not scriptable") if !$aete_handle;
    } else {
        my $RF = OpenResFile($self->{_target});
        if ( !defined($RF) || $RF == 0) {
            croak ("No Resource Fork available for $target");
        }
        $self->{_resource_fork} = $RF;
        $aete_handle = Get1Resource('aete', 0);
        if (!defined($aete_handle) || $aete_handle == 0) {
            croak("Application is not scriptable (App.pm)");
        }
        $self->{_resource} = $aete_handle;
    }
    $self = Parser->new($aete_handle, $target);

    return bless $self, $type;
}

sub DESTROY {
    my $self = shift;
    CloseResFile $self->{_resource_fork} if defined $self->{_resource_fork};
}


sub get_app_status_and_launch
{
    my ($app_path) = @_;
    my ($name, $path, $suffix, $running, $ok_to_launch, $pname, $launch);
    my ($psn, $psi);
    
    $running = 0;
    fileparse_set_fstype("MacOS");
    ($name,$path,$suffix) = fileparse($app_path, "");
    while (($psn, $psi) = each(%Process)) {
        $pname = $psi->processName;
#        print "$pname", "   $name\n";
        $running = 1, last if $pname eq $name;
    }
    if (!$running) {
        my $RF = OpenResFile($app_path);
        if (!defined($RF) || $RF == 0) {
            croak ("No Resource Fork available for $app_path");
        }
        my $check_resource =  Get1Resource('scsz', 0);
        if (!defined($check_resource) || $check_resource == 0) {
            $check_resource = Get1Resource('scsz', 128);
        }
        $ok_to_launch = defined($check_resource) && $check_resource;
        CloseResFile($RF); # don't do anything with the resource now!
        if ($ok_to_launch) {            
            $launch = new LaunchParam(
                launchControlFlags => eval(launchContinue + launchNoFileFlags + launchDontSwitch),
                launchAppSpec => $app_path
                );
            LaunchApplication $launch;
            $running = 1;
        }
    }
    
    while (($psn, $psi) = each(%Process)) {
        $pname = $psi->processName;
        $running = 1, last if $pname eq $name;
    }
    $name = $app_path if $name !~ /:/;
    ($name, $running);
}

sub get_aete_via_event
{
    my($target) = @_;
    my $info = FSpGetFInfo($target);
    
    my $addr_desc = AECreateDesc(typeApplSignature, $info->fdCreator);        
    my $event = AEBuildAppleEvent('ascr', 'gdte', 'sign', $info->fdCreator, 0, 0, , "'----':0");
    my $reply = AESend($event, kAEWaitReply);
    my @handles;
    if ($reply) {
        my $result_desc = AEGetParamDesc($reply, keyDirectObject);
        if ($result_desc->type eq typeAEList) {
            for (my $i = 1; $i <= AECountItems($result_desc); $i++) {
                my $tmp_desc = AEGetNthDesc($result_desc, $i)
                    or croak("Bad result from GetAETE!\n");
                my $aete_handle = $tmp_desc->data
                    or croak("Bad result from GetAETE!\n");
                my $aete = new Handle($aete_handle->get)
                    or croak("Bad result from GetAETE!\n");
                push @handles, $aete;
            }
       } else {
            my $aete_handle = $result_desc->data
                or croak("Bad result from GetAETE!\n");
            my $aete = new Handle($aete_handle->get)
                or croak("Bad result from GetAETE!\n");
            push @handles, $aete;
        }
        AEDisposeDesc $result_desc;
        AEDisposeDesc $reply;
    }
    AEDisposeDesc $event;
    AEDisposeDesc $addr_desc;
    \@handles;
}

