xquery version "1.0";

(:~ application-global functions 
 :
 : mostly authentication issues.
 :
 : Open Siddur Project
 : Copyright 2010-2011 Efraim Feinstein <efraim.feinstein@gmail.com>
 : Licensed under the GNU Lesser General Public License, version 3 or later 
 : $Id: app.xqm 775 2011-05-01 06:46:55Z efraim.feinstein $ 
 :)
module namespace app="http://jewishliturgy.org/modules/app";

import module namespace response="http://exist-db.org/xquery/response";
import module namespace request="http://exist-db.org/xquery/request";
import module namespace session="http://exist-db.org/xquery/session";
import module namespace xmldb="http://exist-db.org/xquery/xmldb";
import module namespace util="http://exist-db.org/xquery/util";

import module namespace paths="http://jewishliturgy.org/modules/paths"
	at "paths.xqm";

declare namespace exist="http://exist.sourceforge.net/NS/exist";
declare namespace xsl="http://www.w3.org/1999/XSL/Transform";
declare namespace err="http://jewishliturgy.org/errors";

(:~ return application version as a string :)
declare function app:get-version(
	) as xs:string {
	string(doc('/code/apps/version.xml')/version)
};

(:~ return decoded authorization string (username, password) or empty 
 : This will probe (in the following order)for:
 : HTTP Basic authentication information
 : 'Authorization' session attribute (containing the HTTP-basic like auth string)
 : 'Authorization' session cookie (containing the HTTP-basic-like auth string)
 : 'user' and 'password' request parameters 
 : 'Username' and 'password' headers    
 :)
declare function app:_get_auth_string() as xs:string* {
  let $authorization := (substring-after(request:get-header('Authorization'),'Basic '))[.]
    cast as xs:base64Binary?
  let $user-name-attribute := session:get-attribute('app.user')[.]
  let $password-attribute := session:get-attribute('app.password')[.]
  let $auth-cookie := request:get-cookie-value('Authorization')[.]
  let $user-name-basic := substring-before(
      util:binary-to-string(($authorization, $auth-cookie)[1]),
      ':')[.]
  let $password-basic := substring-after(
      util:binary-to-string(($authorization, $auth-cookie)[1]),
      ':')[.]
  (: user name and password from the header.  BUG workaround: to get around a bug in betterform 3.1, need to take the last 
   : comma separated value :)
  let $user-name-hdr := tokenize(request:get-header('Username'),',')[last()][.]
  let $password-hdr := tokenize(request:get-header('Password'),',')[last()][.]
  (: last resort: user name and password from parameters user= and password= :)
  let $user-name-param := request:get-parameter('user',())
  let $password-param := request:get-parameter('password',())
  (: return values :)
  let $username := ($user-name-basic, $user-name-hdr, $user-name-attribute, $user-name-param)[1]
  let $password := ($password-basic, $password-hdr, $password-attribute, $password-param)[1]
  return (
  	if ($paths:debug)
  	then
	  	util:log-system-out(
	  		<authenticate>
	  			<uri>{request:get-uri()}</uri>
	  			<header>{$authorization, exists($authorization)}</header>
	  			<attribute>{$user-name-attribute, exists($user-name-attribute)}</attribute>
	  			<cookie>{$auth-cookie, exists($auth-cookie)}</cookie>
	  			<hdr>{$user-name-hdr, $password-hdr, exists($user-name-hdr)}</hdr>
	  			<user-param>{$user-name-param, $password-param, exists($user-name-param)}</user-param>
	  			<return>
	  				<user>{$username}</user>
	  				<password>{$password}</password>
	  			</return>
	  		</authenticate>
	  	)
	  else (),
  	$username, $password)
};

(:~ generate a uuid that is guaranteed not to collide with any of the 
 : strings in $collisions 
 : @param $prefix prefix to add before the proposed uuid to make an xml:id
 : @param $root document node from which we need to make the xml:ids unique
 :)
declare function app:unique-xmlid(
	$prefix as xs:string,
	$root as document-node()
	) as xs:string {
	let $proposal := concat($prefix, util:uuid())
	let $collisions := 
		for $xmlid in $root//@xml:id
		return string($xmlid) 
	return
		if ($proposal = $collisions)
		then app:unique-xmlid($prefix, $root)
		else $proposal
};

(:~ Authenticate and return authenticated user.  
 : HTTP Basic authentication and Username/Password in header takes priority
 : over the logged in user. :)
declare function app:auth-user()
  as xs:string? {
  (session:get-attribute('app.user'), xmldb:get-current-user()[not(. = 'guest')], app:_get_auth_string()[1])[1]
};

(:~ Return authenticated user's password; only works for HTTP Basic authentication :)
declare function app:auth-password()
  as xs:string? {
  (session:get-attribute('app.password'), app:_get_auth_string()[2])[1]
};

(:~ Read HTTP headers to determine if the user can be logged in or is already logged in.  
 : If so, log in to the resource
 : @return true() on success, false() on failure
 :)
declare function app:authenticate()
  as xs:boolean {
  let $authorization as xs:string* := app:_get_auth_string()
  let $user-name as xs:string? := $authorization[1]
  let $password as xs:string? := $authorization[2]
  let $logged-in as xs:boolean := boolean(xmldb:get-current-user()[not(. = 'guest')])
  return (
  	if ($paths:debug)
  	then
  		util:log-system-out(('authenticate() : get-auth-string is ', $authorization))
  	else (), 
  	$logged-in or (
    if ($user-name and $password)
    then (
    	xmldb:login('/db', $user-name, $password),
    	if ($paths:debug)
    	then
    		util:log-system-out(('logging you in as :', $user-name))
    	else ()
    )
    else false() )
    )
};

(:~ specify that authentication (aside from guest) is required
 : to perform any following operations.
 : if the user is not authenticated, return status code 401 with a request for HTTP basic
 : authentication
 :)
declare function app:require-authentication(
	) as xs:boolean {
	app:authenticate() or (
    false(), 
    response:set-status-code(401), 
    response:set-header('WWW-Authenticate', 'Basic')
  )
};

(: return the db-relative path of the called URI context :)
declare function app:context-path() 
  as xs:string? {
  substring-after(request:get-uri(), 
    string-join((request:get-context-path(),request:get-servlet-path()),''))
};

(: Return the resource in the URI context :)
declare function app:context-resource() 
  as document-node()? {
  let $path := app:context-path()
  return
    if (doc-available($path))
    then doc($path)
    else ()
};

(:~ make a collection path that does not exist; (like mkdir -p)
 : create new collections with the given mode, owner and group
 : @param $path directory path
 : @param $origin path begins at
 : @param $owner owner user of any new collections
 : @param $group owner group of any new collections
 : @param $mode permissions mode of any new collections
 :)
declare function app:make-collection-path(
	$path as xs:string, 
	$origin as xs:string,
	$owner as xs:string,
	$group as xs:string,
	$mode as xs:integer) 
	as empty() {
	let $origin-sl := 
		if (ends-with($origin, '/'))
		then $origin
		else concat($origin, '/')
	let $path-no-sl :=
		if (starts-with($path, '/'))
		then substring($path, 2)
		else $path
	let $first-part := substring-before($path-no-sl, '/')
	let $second-part := substring-after($path-no-sl, '/')
	let $to-create := 
		if ($first-part) 
		then $first-part 
		else $path-no-sl
	return
		if ($to-create)
		then 
			let $current-col := concat($origin-sl, $to-create)
			return (
				if (xmldb:collection-available($current-col))
				then (
					if ($paths:debug)
					then
						util:log-system-out(($current-col, ' already exists'))
					else ()
				)
				else (
					if ($paths:debug)
					then
						util:log-system-out(($origin-sl, $to-create, ' creating'))
					else (),
					if (xmldb:create-collection($origin-sl, $to-create))
					then xmldb:set-collection-permissions($current-col, $owner, $group, $mode)
					else error(xs:QName('err:CREATE'), concat('Cannot create collection', $origin-sl, $to-create))
				),
				if ($second-part) 
				then app:make-collection-path($second-part, $current-col, $owner, $group, $mode)
				else ()
				)
		else ()
};

(:~ obfuscate an email address if the user is not logged in
 : @param $address Address to obfuscate
 :)
declare function app:obfuscate-email-address(
	$address as xs:string) 
	as xs:string {
	if (app:auth-user())
	then $address
	else string-join(
		(substring($address, 1, 2), 
		substring($address, string-length($address)-1, 2))
		,'...')
};

(:~ expand a given data set so it covers prototype
 : all of the elements and attributes in a prototype.
 : The xml:id "new" is special. 
 : tei:name will be collapsed unless $collapse-names is false
 :)
declare function app:expand-prototype(
	$data as element(),
	$prototype as element(),
	$collapse-names as xs:boolean)
	as element() {
	let $transform :=
		<xsl:stylesheet version="2.0" 
			xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
			xmlns:xs="http://www.w3.org/2001/XMLSchema"
			exclude-result-prefixes="xs">		
			<xsl:output encoding="utf-8" indent="yes" method="xml"/>
    	<xsl:strip-space elements="*"/>
    
    	<xsl:include href="{$paths:rest-prefix}{$paths:modules}/prototype.xsl2"/>
    	<xsl:param name="prototype" as="element()">
    		{$prototype}
    	</xsl:param>
    
    	<xsl:template match="/*">
    		<xsl:for-each select="*">
    			<xsl:apply-templates select="$prototype">
 						<xsl:with-param name="data" as="element()" select=".">
 						</xsl:with-param>
 					</xsl:apply-templates>
    		</xsl:for-each>
    	</xsl:template>
		</xsl:stylesheet>
	return
		transform:transform($data, $transform, 
			<parameters>
				<param name="collapse-names" value="{if ($collapse-names) then 'true' else ''}" />
			</parameters>)
};

(:~ contract a given data set so it doesn't include empty attributes
 :)
declare function app:contract-data(
	$data as element(),
	$expand-names as xs:boolean)
	as element() {
	let $transform :=
		<xsl:stylesheet version="2.0" 
			xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
			xmlns:xs="http://www.w3.org/2001/XMLSchema"
      xmlns:tei="http://www.tei-c.org/ns/1.0"
			exclude-result-prefixes="xs">		
      {
      if ($expand-names)
      then 
        <xsl:import href="{$paths:rest-prefix}{$paths:modules}/name.xsl2"/>
      else ()
      }
			<xsl:output encoding="utf-8" indent="yes" method="xml"/>
    	<xsl:strip-space elements="*"/>

    	<xsl:include href="{$paths:rest-prefix}{$paths:modules}/relevance.xsl2"/>
      
      <!-- convert name text into expanded names -->
      {
      if ($expand-names)
      then (
        <xsl:template match="tei:name/text()">
          <xsl:call-template name="split-name"/>
        </xsl:template>
      )
      else ()
      }

    	<xsl:template match="/*" priority="10">
        <xsl:copy>
          <xsl:copy-of select="@*"/>
          <xsl:apply-templates/>
        </xsl:copy>
    	</xsl:template>
		</xsl:stylesheet>
	return
		transform:transform($data, $transform, ())
};


(:~ return a formatted error message, assuming an error occurred :)
declare function app:error-message() 
  as element(error) {
  <error xmlns="">
    <exception>Error: {$util:exception-message}</exception>
  </error>
};

(:~ return a formatted error message, infixed in the original data element :)
declare function app:error-message(
	$original-data as element()?
	) 
  as element() {
  if ($original-data) 
  then
	  element {QName(namespace-uri($original-data), name($original-data))} {
	  	$original-data/@*,
	  	$original-data/*,
	  	app:error-message()
	  }
	else app:error-message()
};

(:~ concatenate two components together as a path, making sure that the result
 : is separated by a / :)
declare function app:concat-path(
  $a as xs:string,
  $b as xs:string
  ) as xs:string {
  let $a-s := 
    if (ends-with($a,'/'))
    then $a
    else concat($a, '/')
  let $b-s :=
    if (starts-with($b, '/'))
    then substring($b, 2)
    else $b
  return
    concat($a-s, $b-s)
};

(:~ concatenate a sequence of strings together as a path :)
declare function app:concat-path(
  $a as xs:string+
  ) as xs:string {
  let $n := count($a)
  return
  	if ($n = 1)
  	then $a
  	else if ($n = 2)
  	then app:concat-path($a[1], $a[2])
  	else app:concat-path((subsequence($a,1,$n - 2), app:concat-path($a[$n - 1], $a[$n])))
};



(:~ perform an XSLT transformation stored in the database on a document stored in the database
 : This function is a kluge 
 : @param $document-uri Pointer to the document in the database, *must* be absolute relative to db
 : 	Alternatively, if $document-uri contains a node(), the node() is transformed
 : @param $xslt-uri Pointer to the XSLT in the database, *must* be absolute relative to db
 : @param $parameters Parameters to pass to the XSLT 
 : @param $mode mode to execute; use empty sequence or blank string for #default
 :)
declare function app:transform-xslt(
  $document-uri as item(),
  $xslt-uri as xs:string,
  $parameters as element(param)*,
  $mode as xs:string?
  ) as item()* {
  let $xslt-uri-abs := 
    (:concat('xmldb:exist://', $xslt-uri):)
    app:concat-path($paths:rest-prefix, $xslt-uri)
  let $user := app:auth-user()
  let $password := app:auth-password()
  let $absolute-uri := 
    concat('xmldb:exist://', 
      if ($user)
      then concat($user,':',$password,'@')
      else '', 
      $document-uri)
(:  	app:concat-path($paths:rest-prefix, $document-uri)
    	string-join((
      	$document-uri,
      	if ($user)
      	then ( 
      		if (contains($document-uri, '?')) then '&amp;' else '?',
          'auth=', app:encode-auth-string($user, $password)
      		'user=', $user, '&amp;password=', $password
      	)
      	else ()
      	), '') ):)
  let $xslt :=
    <xsl:stylesheet 
      xmlns:xsl="http://www.w3.org/1999/XSL/Transform" 
      xmlns:app="http://jewishliturgy.org/modules/app"
      version="2.0"
      exclude-result-prefixes="app">
      <xsl:include href="{$xslt-uri-abs}"/>
      <xsl:template match="app:root">
      	<xsl:variable name="to-apply" as="document-node()">{
      		if ($document-uri instance of node())
      		then
      			<xsl:document>{$document-uri}</xsl:document>
      		else 
      			attribute {'select'}{concat('doc("', $absolute-uri, '")')}
        }</xsl:variable>
        <xsl:apply-templates select="$to-apply">
        {
        if ($mode) 
        then attribute {'mode'}{$mode}
        else ()
        }
        </xsl:apply-templates>
      </xsl:template>
    </xsl:stylesheet>
  return (
  	if ($paths:debug)
  	then
    	util:log-system-out(('Running XSLT (as ', $user,':',$password,'=',xmldb:get-current-user(),') ', $xslt-uri-abs, ' on ', if ($document-uri instance of node()) then 'node' else $absolute-uri))
    else (),
    transform:transform(<app:root/>, $xslt, (
    	if ($parameters or $user) 
    	then 
    		<parameters>{
    			$parameters, 
    			if ($user) 
    			then (
    				<param name="user" value="{$user}"/>,
    				<param name="password" value="{$password}"/> 
    			)
    			else ()
    		}</parameters>
    	else ()
    	)
    )
  )
};

(:~ store login credentials in the session 
 : @param $user login username
 : @param $password login password
 :) 
declare function app:login-credentials(
	$user as xs:string,
	$password as xs:string
	) as empty() {
	session:set-attribute('app.user', $user),
	session:set-attribute('app.password', $password)
};

(:~ remove login credentials from the session :)
declare function app:logout-credentials(
	) as empty() {
	session:invalidate()
};

(:~ pass login credentials from the session to an XQuery
 : This function should be used inside <exist:dispatch/> 
 :)
declare function app:pass-credentials-xq(
	) as element()+ {
	local:pass-credentials('xquery')
};

(:~ pass login credentials from the session to an XSLT
 : This function should be used inside <exist:dispatch/> 
 :)
declare function app:pass-credentials-xsl(
	) as element()+ {
	local:pass-credentials('xslt')
};

(:~ pass credentials to next xquery or xslt, depending on $type
 : @param $type either 'xquery' or 'xslt'
 :)
declare function local:pass-credentials(
	$type as xs:string
	) as element()+ {
	let $user := session:get-attribute('app.user')
	let $password := session:get-attribute('app.password')
	return (
		<exist:set-attribute name="{$type}.user" value="{$user}"/>,
		<exist:set-attribute name="{$type}.password" value="{$password}"/>
	)			
};

(:~ forward from a controller to an identity view to display protected XML
 : Use within <exist:dispatch/> as the last view
 :) 
declare function app:identity-view(
	) as element() {
	app:identity-view(())
};

(:~ forward from a controller to an identity view to display protected XML
 : Use within <exist:dispatch/> as the last view
 :) 
declare function app:identity-view(
	$uri as xs:string?
	) as element() {
	<exist:forward url="/code/queries/identity.xql">
		{
		if ($uri)
		then
			<exist:add-parameter name="uri" value="{$uri}" />
		else ()
		}
	</exist:forward>
};
