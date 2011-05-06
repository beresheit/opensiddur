xquery version "1.0";
(:~ not available yet placeholder
 : 
 : Open Siddur Project
 : Copyright 2011 Efraim Feinstein <efraim@opensiddur.org>
 : Licensed under the GNU Lesser General Public License, version 3 or later
 :)  
import module namespace app="http://jewishliturgy.org/modules/app" 
 	at "/code/modules/app.xqm";
import module namespace builder="http://jewishliturgy.org/apps/builder/controls" 
	at "/code/apps/builder/modules/builder.xqm";
import module namespace collab="http://jewishliturgy.org/modules/collab" 
 	at "/code/modules/collab.xqm";
import module namespace controls="http://jewishliturgy.org/modules/controls" 
 	at "/code/modules/controls.xqm";	
import module namespace site="http://jewishliturgy.org/modules/site" 
 	at "/code/modules/site.xqm";
import module namespace login="http://jewishliturgy.org/apps/user/login" 
	at "/code/apps/user/modules/login.xqm";

declare default element namespace "http://www.w3.org/1999/xhtml";
declare namespace ev="http://www.w3.org/2001/xml-events";
declare namespace html="http://www.w3.org/1999/xhtml";
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace xf="http://www.w3.org/2002/xforms";

declare option exist:serialize "method=xhtml media-type=text/xml indent=yes omit-xml-declaration=no
	process-xsl-pi=no
	doctype-public=-//W3C//DTD&#160;XHTML&#160;1.1//EN
	doctype-system=http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd"; 

let $login-instance-id := 'login'
let $builder-instance-id := 'builder'
return
	site:form(
		<xf:model>{
			login:login-instance($login-instance-id, 
				(site:sidebar-login-actions-id(), builder:login-actions-id($builder-instance-id))
			),
			builder:login-actions($builder-instance-id),
			<xf:instance id="resource">
				<resource xmlns="">
					<item/>
				</resource>
			</xf:instance>
		}</xf:model>,
		<title>Open Siddur Builder</title>,
		<fieldset>
			<div>
				The requested siddur document was not found or is inaccessible. Return to 
				<a href="{$builder:app-location}/my-siddurim.xql">My siddurim</a> to select a siddur
				or <a href="{$builder:app-location}/edit-metadata.xql?new=true">start a new one</a>.
			</div>
		</fieldset>,
		(site:css(), builder:css()),
		site:header(),
		(site:sidebar-with-login($login-instance-id),
		builder:sidebar()),
		site:footer(),
		builder:app-header($builder-instance-id, 'app-header', (), ())
	)