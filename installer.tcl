# A very special library used to support the ACS installer. Sourced only
# when there's no database driver available, or [ad_verify_install]
# returns false.
#
# If no database driver is available, the acs-kernel libraries may not have
# been loaded (which is fine, since index.tcl will display a message
# instructing the user to install the Oracle driver and restart the server
# before proceeding any further; in this case we won't use any procedures
# depending on the core libraries). Otherwise, all -procs.tcl files in
# acs-kernel (but not any -init.tcl files) will have been run.

# Return a header for an installation page, suitable for ns_writing.
# This procedure engages the installer mutex, as every installer page is a critical section.

ad_proc -private install_input_widget { 
    {-type ""}
    {-size 40}
    {-extra_attributes ""}
    {-value ""}
    param_name 
} {
    Return an HTML input widget for a parameter with an
    indication of whether the param is mandatory.
} {
    set type_attribute [ad_decode $type "" "" "type=\"$type\""]

    if { ![empty_string_p $value] } {
        append extra_attributes " value=\"[ad_quotehtml $value]\""
    }
    
    set input_widget "<input name=\"$param_name\" size=\"$size\" $type_attribute $extra_attributes>"

    if { [install_param_mandatory_p $param_name] } {
        append input_widget " <span style=\"color: red;\">\[*\]</span>"
    }

    return $input_widget
} 

ad_proc -private install_param_mandatory_p { param_name } {
    Return 1 if the given parameter with given name is
    mandatory for OpenACS install and 0 otherwise.

    @author Peter Marklund
} {
    array set mandatory_params_array [install_mandatory_params]
    set mandatory_names [array names mandatory_params_array]
    return [expr [lsearch -exact $mandatory_names $param_name] != -1]
}

ad_proc -private install_mandatory_params {} {
    Return information about parameters that are mandatory
    for OpenACS installation.

    @return An array list with variable names as values
            and pretty names as keys.
} {
    return {
        email "Email"
        first_names "First names"
        last_name "Last name"
        password "Password"
        password_confirmation "Password confirmation"
        system_url "System URL"
        system_name "System name"
        publisher_name "Publisher name"
    }
}

ad_proc -private install_optional_params {} {
    Return information about parameters that are optional
    for OpenACS installation.

    @return An array list with variable names as values
            and default values as keys.
} {
    return  {
        username ""
        system_owner ""
        admin_owner ""
        host_administrator ""
        outgoing_sender ""
        new_registrations ""
    }
}

ad_proc -private install_page_contract { mandatory_params optional_params } {
    Instead of using ad_page_contract that relies on certain acs-subsite libraries
    that may not be available at all times during installation we use this
    more primitive proc instead.

    @param mandatory_params An array list where keys are param names and values
                            are pretty names.
    @param optional_params An array list with param names as keys and default
                           values as keys.

    @author Peter Marklund
} {
    array set mandatory_params_array $mandatory_params
    array set optional_params_array $optional_params

    set form [ns_getform]
    set missing_params [list]

    if { [empty_string_p $form] } {
        # Form is empty - all mandatory params are missing
        foreach param_name [array names mandatory_params_array] {
            lappend missing_params $mandatory_params_array($param_name)
        }
    } else {
        # Form is non-empty

        # Loop over all params
        set all_param_names [concat [array names mandatory_params_array] \
                                 [array names optional_params_array]]
        foreach param_name $all_param_names {
            set param_value [ns_set iget $form $param_name]
            set mandatory_p [expr [lsearch -exact $mandatory_params $param_name] != -1]

            if { ![empty_string_p $param_value] } {
                # Param in form - set value in callers scope
                uplevel [list set $param_name $param_value]
            } else {
                # Param not in form
                if { $mandatory_p } {
                    # Mandatory param - complain
                    lappend missing_params $mandatory_params_array($param_name)
                } else {
                    # Optional param - set default
                    uplevel [list set $param_name $optional_params_array($param_name)]
                }
            }
        }
    }

    # If there are missing mandatory params - return a complaint
    # page and exit
    if { [llength $missing_params] > 0 } {
        ns_write "[install_header 200 "Missing parameters"]

The following mandatory parameters are missing:
<ul>
<li>[join $missing_params "</li>\n<li>"]</li>
</ul>

<p>
Please back up your browser and provide those parameters. Thank you.
</p>

[install_footer]
"
        return -code return
    }
}

proc install_header { status title } {

    # Prefix the page title
    set page_title_prefix "OpenACS Installation"
    if { ![empty_string_p $title] } {
        set page_title "${page_title_prefix}: $title"
    } else {
        set page_title $page_title_prefix
    }

    return "HTTP/1.0 $status OK
MIME-Version: 1.0
Content-Type: text/html

<html>
  <head>
    <title>$page_title</title>
  </head>
  <body bgcolor=white>
    <h2>$page_title</h2>
    <hr>
"
}

# Return a footer for an installation page, suitable for ns_writing.
# This procedure must be called at the end of every installer page to end the critical section.
proc install_footer {} {
    return "<hr>
<a href=\"mailto:gatekeepers@openacs.org\"><address>gatekeepers@openacs.org</address></a>

  </body>
</html>
"
}

# Write headers and a whole page.
proc install_return { status title page } {
    ns_write "[install_header $status $title]
$page
[install_footer]"
}

# Write out a bullet item (suitable for use as a callback for, e.g., apm_register_new_packages).
proc install_write_bullet_item { item } {
    ns_write "$item<li>\n"
}

# Does the ACS kernel data model seem installed?
proc install_good_data_model_p {} {
    foreach table_name { acs_objects sec_session_properties } {
	if { ![db_table_exists $table_name] } {
	    return 0
	}
    }
    return 1
}

# Returns a simple next button.
proc install_next_button { url } {
    return "<form action=$url method=get><center><input type=submit value=\"Next ->\"></center></form>"
}


proc install_file_serve { path } {
    if {[file isdirectory $path] && [string index [ad_conn url] end] != "/" } {
  	ad_returnredirect "[ad_conn url]/"
    } else {
	ns_log Debug "Installer serving $path"
	ad_try {
	    rp_serve_abstract_file $path
	} notfound val {
	    install_return 404 "Not found" "
	    The file you've requested, doesn't exist. Please check
	    your URL and try again."
	} redirect url {
	    ad_returnredirect $url
	} directory dir_index {
	    set new_file [file join $path "index.html"]
	    if {[file exists $new_file]} {
		rp_serve_abstract_file $new_file
	    } 
	    set new_file [file join $path "index.adp"]
	    if {[file exists $new_file]} {
		rp_serve_abstract_file $new_file
	    } 
	}
    }
}

# The preauth filter which serves installation scripts.
proc install_handler { conn arg why } {
    # Redirect requests to /doc appropriately.  Thus, the installer can reference the install guide.
    if { [regexp {/doc(.*)} [ad_conn url] "" doc_url] } {
	set doc_urlv [split [string trimleft $doc_url] /]
	set package_key [lindex $doc_urlv 1]
	ns_log Debug "Scanning $doc_url with package_key $package_key..."
	if {[file isfile "[acs_root_dir]/packages/acs-core-docs/www[join $doc_urlv /]"]} {
	    install_file_serve "[acs_root_dir]/packages/acs-core-docs/www[join $doc_urlv /]"
	} elseif {[file isdirectory \
		"[acs_root_dir]/packages/acs-core-docs/www[join $doc_urlv /]"]} {
	    install_file_serve "[acs_root_dir]/packages/acs-core-docs/www[join $doc_urlv /]"
	} elseif {[file isdirectory "[acs_root_dir]/packages/$package_key/www/doc"]} {
	    install_file_serve "[acs_root_dir]/packages/$package_key/www/doc[join [lrange $doc_urlv 2 end] /]"
	} else {
	    install_file_serve "[acs_root_dir]/packages/$package_key/doc[join $doc_url /]"
	}
	return "filter_return"
    }

    # Make sure any requests to /SYSTEM still get through.  This is useful if your server
    # is setting behind a load balancer that uses SYSTEM pages to verify that the server
    # is still working.
    if { [regexp {/SYSTEM/(.*)} [ad_conn url] "" system_file] } {
	if {[string compare [string range $system_file \
		[expr [string length $system_file ] - 4] end] ".tcl"
	]} {
	    set system_file "$system_file.tcl"
	}
	apm_source "[acs_root_dir]/www/SYSTEM/$system_file"
	return "filter_return"
    }

    if { ![regexp {/([a-zA-Z0-9\-_]*)$} [ad_conn url] "" script] } {
	ad_returnredirect "/"
	return
    }

    if { ![string compare $script ""] } {
	set script "index"
    }

    set path "[nsv_get acs_properties root_directory]/packages/acs-bootstrap-installer/installer/$script.tcl"
    if { ![info exists path] } {
	install_return 404 "Not found" "
The installation script you've requested, <code>$script</code>, doesn't exist. Please check
your URL and try again.
"
    }
    # Engage a mutex for double-click protection.
    ns_mutex lock [nsv_get acs_installer mutex]
    if { [catch {
	# Source the page and then unlock the mutex.
	apm_source $path
	ns_mutex unlock [nsv_get acs_installer mutex]
    } error] } {
	# In case of an error, don't forget to unlock the mutex.
	ns_mutex unlock [nsv_get acs_installer mutex]
	global errorInfo
	install_return 500 "Error" "The following error occurred in an installation script:

<blockquote><pre>[ns_quotehtml $errorInfo]</pre></blockquote>
"

    }
    return "filter_return"
}

proc install_admin_widget {} {

    return "
	<form action=create-administrator>
	<input type=hidden name=done_p value=1>
	<center>
	<input type=submit value=\"Create Administrator ->\">
	</center>
"

}

proc install_redefine_ad_conn {} {

    # Peter Marklund
    # We need to be able to invoke ad_conn in the installer. However
    # We cannot use the rp_filter that sets up ad_conn
    proc ad_conn { args } {
        set attribute [lindex $args 0]

        if { [string equal $attribute "-connected_p"] } {
            set return_value 1
        } elseif { [catch {set return_value [ns_conn $attribute] } error] } {
            set return_value ""
        }

        return $return_value
    }
}

ad_proc -public ad_windows_p {} {
    # DLB - this used to check the existence of the WINDIR environment
    # variable, rather than just asking AOLserver.
    Returns 1 if the ACS is running under Windows.
    Note,  this procedure is a best guess, not sure of a better way of determining:
} {
    set thisplatform [ns_info platform]
    if {[string equal $thisplatform  "win32" ]} {
       return 1
    } else {
       return 0
    }
}

ad_proc -private install_do_data_model_install {} {
    Installs the kernel datamodel.
} {
    ns_write "
    Installing the OpenACS kernel data model...
    <blockquote><pre>
    "
    cd [file join [acs_root_dir] packages acs-kernel sql [db_type]]
    db_source_sql_file -callback apm_ns_write_callback acs-kernel-create.sql

    # DRB: Now initialize the APM's table of known database types.  This is
    # butt-ugly.  We could have apm-create.sql do this but that would mean
    # adding a new database type would require editing two places (the very
    # obvious list in bootstrap.tcl and the less-obvious list in apm-create.sql).
    # On the other hand, this is ugly because now this code knows about the
    # apm datamodel as well as the existence of the special acs-kernel module.

    set apm_db_types_exists [db_string db_types_exists "
        select case when count(*) = 0 then 0 else 1 end from apm_package_db_types"]

    if { !$apm_db_types_exists } {
        ns_log Notice "Populating apm_package_db_types"
        foreach known_db_type [db_known_database_types] {
            set db_type [lindex $known_db_type 0]
            set db_pretty_name [lindex $known_db_type 2]
            db_dml insert_apm_db_type {
                insert into apm_package_db_types
                    (db_type_key, pretty_db_name)
                values
                    (:db_type, :db_pretty_name)
            }
        }
    }

    ns_write "</pre></blockquote>

    Done installing the OpenACS kernel data model.<p>

    "

    # Some APM procedures use util_memoize, so initialize the cache 
    # before starting APM install
    apm_source "[acs_package_root_dir acs-tcl]/tcl/20-memoize-init.tcl"

    apm_version_enable -callback apm_ns_write_callback [apm_package_install -callback apm_ns_write_callback "[file join [acs_root_dir] packages acs-kernel acs-kernel.info]"]

    ns_write "<p>Loading package .info files.<p>"

    # Preload all the .info files so the next page is snappy.
    apm_dependency_check -initial_install [apm_scan_packages -new [file join [acs_root_dir] packages]]

    ns_write "Done loading package .info files<p>"    
}

ad_proc -private install_do_packages_install {} {
    Installs all packages during OpenACS install.
} {
    proc ad_acs_kernel_id {} {
        if {[db_table_exists apm_packages]} {
    	return [db_string acs_kernel_id_get {
    	    select package_id from apm_packages
    	    where package_key = 'acs-kernel'
    	} -default 0]
        } else {
            return 0
        }
    }

    ns_write "Installing OpenACS Core Services"

    # Load the acs-tcl init files that might be needed when installing, instantiating and mounting packages
    # We shouldn't source request-processor-init.tcl as it might interfere with the installer request handler
    foreach { init_file } { utilities-init.tcl site-nodes-init.tcl } {
        ns_log Notice "Loading acs-tcl init file $init_file"
        apm_source "[acs_package_root_dir acs-tcl]/tcl/$init_file"
    }
    apm_bootstrap_load_libraries -procs acs-subsite
    apm_bootstrap_load_queries acs-subsite
    install_redefine_ad_conn

    # Attempt to install all packages.
    set dependency_results [apm_dependency_check -initial_install [apm_scan_packages -new [file join [acs_root_dir] packages]]]
    set dependencies_satisfied_p [lindex $dependency_results 0]
    set pkg_list [lindex $dependency_results 1]
    apm_packages_full_install -callback apm_ns_write_callback $pkg_list

    # Complete the initial install.

    if { ![ad_acs_admin_node] } {
        ns_write "  <p><li> Completing Install sequence by mounting the main site and other core packages.<p>
        <blockquote><pre>"

        # Mount the main site
        cd [file join [acs_root_dir] packages acs-kernel sql [db_type]]
        db_source_sql_file -callback apm_ns_write_callback acs-install.sql

        # Make sure the site-node cache is updated with the main site
        site_node::init_cache

        # We need to redefine ad_conn again since apm_package_install resourced the real ad_conn
        install_redefine_ad_conn

        # Mount and set permissions for core packages
        apm_mount_core_packages

        ns_write "</pre></blockquote>"

        # Now process the application bundle if an install.xml file was found.

        if { [file exists [apm_install_xml_file_path]] } {
            set root_node [apm_load_install_xml_file]
            set acs_application(name) [apm_required_attribute_value $root_node name]
            set acs_application(pretty_name) [apm_attribute_value -default $acs_application(name) $root_node pretty-name]

            ns_write "<p>Loading packages for the $acs_application(pretty_name) application.</p>"

            set actions [xml_node_get_children_by_name $root_node actions]
            if { [llength $actions] > 1 } {
                ns_log Error "Error in \"install.xml\": only one action node is allowed"
                ns_write "<p>Error in \"install.xml\": only one action node is allowed<p>"
                return
            }
            set actions [xml_node_get_children [lindex $actions 0]]

            foreach action $actions {

                switch -exact [xml_node_get_name $action] {

                    text {}

                    install {

                        set install_spec_files [list]
                        foreach install_spec_file \
                            [glob -nocomplain "[acs_root_dir]/packages/[apm_required_attribute_value $action package]/*.info"] {
                            if { [catch { array set package [apm_read_package_info_file $install_spec_file] } errmsg] } {
                                # Unable to parse specification file.
                                ns_log Error "$install_spec_file could not be parsed correctly.  The error: $errmsg"	
                                ns_write "<br>install: $install_spec_file could not be parsed correctly.  The error: $errmsg"	
                                return
                            }
                            if { [apm_package_supports_rdbms_p -package_key $package(package.key)] &&
                                 ![apm_package_installed_p $package(package.key)] } {
                                lappend install_spec_files $install_spec_file
                            }
                        }

                        set pkg_info_list [list]
                        foreach spec_file [glob -nocomplain "[acs_root_dir]/packages/*/*.info"] {
                            # Get package info, and find out if this is a package we should install
                            if { [catch { array set package [apm_read_package_info_file $spec_file] } errmsg] } {
                                # Unable to parse specification file.
                                ns_log Error "$spec_file could not be parsed correctly.  The error: $errmsg"	
                                ns_write "<br>install: $spec_file could not be parsed correctly.  The error: $errmsg"	
                                return
                            }

                            if { [apm_package_supports_rdbms_p -package_key $package(package.key)] &&
                                 ![apm_package_installed_p $package(package.key)] } {
                                # Save the package info, we may need it for dependency satisfaction later
                                lappend pkg_info_list [pkg_info_new $package(package.key) $spec_file \
                                    $package(provides) $package(requires) ""]
                            }
                        }

                        if { [llength $install_spec_files] > 0 } {
                            set dependency_results [apm_dependency_check -pkg_info_all $pkg_info_list $install_spec_files]
                            if { [lindex $dependency_results 0] == 1 } {
                                apm_packages_full_install -callback apm_ns_write_callback [lindex $dependency_results 1]
                            } else {
                                foreach package_spec [lindex $dependency_results 1] {
                                    if { [string is false [pkg_info_dependency_p $package_spec]] } {
                                        ns_log Error "install: package \"[pkg_info_key $package_spec]\"[join [pkg_info_comment $package_spec] ","]"
                                        append html "<p>Package \"[pkg_info_key $package_spec]\"\n<ul><li>[join [pkg_info_comment $package_spec] "<li>"]\n</ul>\n"
                                    }
                                }
                                ns_write "$html\n"
                                return
                            }
                        }
                    }

                    mount {

                        set package_key [apm_required_attribute_value $action package]
                        set instance_name [apm_required_attribute_value $action instance-name]
                        set mount_point [apm_required_attribute_value $action mount-point]

                        set parent_id [site_node::get_node_id -url "/"]

                        if { [catch {
                            db_transaction {            
                                set node_id [site_node::new -name $mount_point -parent_id $parent_id]
                            }
                        } error] } {
                            # There is already a node with that path, check if there is a package mounted there
                            array set node [site_node::get -url "/$mount_point"]
                            if { [empty_string_p $node(object_id)] } {
                                # There is no package mounted there so go ahead and mount the new package
                                set node_id $node(node_id)
                            } else {
                                ns_log Error "A package is already mounted at \"$mount_point\""
                                ns_write "<br>mount: A package is already mounted at \"$mount_point\", ignoring mount command."
                                set node_id ""
                            }
                        }

                        if { ![empty_string_p $node_id] } {

                            ns_write "<p>Mounting new instance of package $package_key at /$mount_point<p>"
                            site_node::instantiate_and_mount \
                                -node_id $node_id \
                                -node_name $mount_point \
                                -package_name $instance_name \
                                -package_key $package_key

                        }

                    }

                    set-parameter {
                        set name [apm_required_attribute_value $action name]
                        set value [apm_required_attribute_value $action value]
                        set package_key [apm_attribute_value -default "" $action package]
                        set url [apm_attribute_value -default "" $action url]

                        if { ![string equal $package_key ""] && ![string equal $url ""] } {
                            ns_log Error "set-parameter: Can't specify both package and url"
                            ns_write "<br>set-parameter: Can't specify both package and url"
                            return
                        } elseif { ![string equal $package_key ""] } {
                            parameter::set_from_package_key -package_key $package_key -parameter $name -value $value
                        } else {
                            parameter::set_value \
                                -package_id [site_node::get_object_id -node_id [site_node::get_node_id -url $url]] \
                                -parameter $name \
                                -value $value
                        }
                    }

                    default {
                        ns_log Error "Error in \"install.xml\": got bad node \"[xml_node_get_name $action]\""
                    }

                }

            }
        }
    }


    ns_write "All Packages Installed."
}

# Register the install handler.
ns_register_filter preauth GET * install_handler
ns_register_filter preauth POST * install_handler
ns_register_filter preauth HEAD * install_handler
