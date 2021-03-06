#!/usr/bin/env python
# turn a filesystem directory structure into a "database backup" that can be restored by 
# eXist's admin client
#
# Format of override file:
#   <collection group="" mode="" name="" owner="" exclude="">
#     <subcollection name="" exclude=""/>
#     <resource group="" owner="" name="" mode="" exclude=""/>
#   </collection>
#
# if exclude="true", collection or resource is ignored
#
# An override file can also be used to exclude files by regular expression
#
# Open Siddur Project
# Copyright 2010 Efraim Feinstein
# Licensed under the GNU Lesser General Public License, version 3 or later
#
# $Id: makedb.py 687 2011-01-23 23:36:48Z efraim.feinstein $
import sys
import copy
import re
import os
import getopt
import time
from xml.etree import ElementTree as etree
from xml.dom import minidom

# structure
class Struct:
  pass

# default file properties
class FileProperties:
  user = 'admin'
  group = 'dba'
  permissions = '755'
  fileType = 'binary'
  mimeType = 'application/octet-stream'
  include = True
  

# return a dictionary index of mime types by file extension
def indexMimeTypes(existHome):
  mimeTypesFile = existHome + "/mime-types.xml"
  print "Reading mime types from ", mimeTypesFile
  mimeTree = etree.ElementTree(file=mimeTypesFile)
  mimeDict = {}
  for typeDesc in mimeTree.findall("mime-type"):
    mimeRecord = Struct()
    mimeRecord.mimeType = typeDesc.attrib["name"]  # MIME type
    mimeRecord.fileType = typeDesc.attrib["type"] # xml or binary
    extensionsString = typeDesc.findall("extensions")[0].text
    for extension in extensionsString.split(','):
      mimeDict[extension] = mimeRecord
  return mimeDict

# build a regular expression to check a file name for exclusion
def buildExcludeList(excludeFile):
  excludeStrings = ['(__contents__\\.xml$)','(__override__\\.xml$)','(\\.svn$)','(\\.(bak|bkp|swp)$)','(~$)','(Makefile)']
  if excludeFile:
    ef = file(excludeFile,'r')
    for line in ef:
      excludeStrings.append('(' + line + ')')
    ef.close()
  excludeRE = re.compile('|'.join(excludeStrings))
  return excludeRE

# get created and modified times for a file in ISO format
def fileTimes(fileWithPath):
  def timeToString(t):
    atime = time.localtime(t)
    aString = time.strftime('%FT%X%z',atime)
    return aString[0:-2]+':'+aString[-2:]    # Python doesn't add the colon eXist expects
  
  statinfo = os.stat(fileWithPath)
  return (timeToString(statinfo.st_ctime), timeToString(statinfo.st_mtime))


# index override by filename
# the empty string references the collection
def indexOverrides(overrideXml):
  index = {}
  index[''] = overrideXml.getroot()
  for element in overrideXml.findall('resource'):
    index[element.attrib["name"]] = element
  return index

# incorporate overrides from defaults from __override__.xml 
# one of filename or collection must be given
def incorporateOverrides(overrideXml, overrideIndex, default, filename=''):
  props = copy.copy(default)

  try:
    override = overrideIndex[filename]

    props.include = not('exclude' in override.attrib and override.attrib["exclude"].lower() == 'true')

    try:
      props.mimeType = override.attrib["mimetype"]
    except KeyError:
      pass
    try:
      props.user = override.attrib["user"]
    except KeyError:
      pass
    try:
      props.group = override.attrib["group"]
    except KeyError:
      pass
    try:  
      props.permissions = override.attrib["mode"]
    except KeyError:
      pass
    try:
      fType = override.attrib["type"]
      if fType == 'XMLResource':
        fType = 'xml'
      elif fType == 'BinaryResource':
        fType = 'binary'
    
      props.fileType = ftype
    except KeyError:
      pass
  except KeyError:
    pass
  
  return props

# recursively build __content__.xml for each directory
def buildCollection(srcDirectory, destCollection, default, mimeDict, excludeRE):
  exNS = '{http://exist.sourceforge.net/NS/exist}'
  contentOverrideFile = os.path.join(srcDirectory,'__override__.xml')
  hasOverrides = os.path.exists(contentOverrideFile)
  if hasOverrides:
    overrideXml = etree.parse(contentOverrideFile)
    overrideIndex = indexOverrides(overrideXml)
    props = incorporateOverrides(overrideXml, overrideIndex, default, '')
  else:
    props = default

  if props.include:
    (directoryCtime, directoryMtime) = fileTimes(srcDirectory)
    contentsXml = etree.Element(exNS + 'collection', {'name':destCollection, 'version':'1',   
      'mode':props.permissions, 'owner':props.user, 'group':props.group, 'created':directoryCtime})
    contentsXmlTree = etree.ElementTree(contentsXml)

    for fname in os.listdir(srcDirectory):
      fileWithPath = os.path.join(srcDirectory,fname)
      if hasOverrides:
        props = incorporateOverrides(overrideXml, overrideIndex, default, fname)
      else:
        props = default
      if (not excludeRE or not excludeRE.search(fileWithPath)) and props.include:    # exclude anything listed in the exclude file
        if os.path.isdir(fileWithPath):
          # add subcollection to contentsXml
          etree.SubElement(contentsXml, exNS + 'subcollection', {'filename':fname, 'name':fname})
          # recurse to next directory
          buildCollection(fileWithPath, os.path.join(destCollection, fname), default, mimeDict, excludeRE)
        else:
          (fCtime, fMtime) = fileTimes(fileWithPath)
          (base, ext) = os.path.splitext(fname)
          try:
            mimeRecord = mimeDict[ext]
            fMime = mimeRecord.mimeType
            fType = mimeRecord.fileType
          except:
            fMime = props.mimeType
            fType = props.fileType

          if fType == 'xml':
            fType = 'XMLResource'
          else:
            fType = 'BinaryResource'

          # add resource to contentsXml
          # TODO: namedoctype, publicid, systemid
          etree.SubElement(contentsXml, exNS + 'resource', {'filename':fname, 'name':fname, 
            'owner':props.user, 'group':props.group, 'mode':props.permissions, 
            'mimetype':fMime, 'type':fType})

    # write the contentsXml file
    unindented = etree.tostring(contentsXml, encoding='utf-8')
    reparsed = minidom.parseString(unindented)
    outputFile = file(os.path.join(srcDirectory,'__contents__.xml'),'w')
    outputFile.write(reparsed.toprettyxml(indent="  "))
    outputFile.close()

def usage():
  print "Usage: ", sys.argv[0], " [options] directory"
  print "  -h, --home          eXist home directory (default $EXIST_HOME)"
  print "  -c, --collection    destination base collection in the database (default /db)"
  print "  -p, --permissions    octal code for file permissions (default 755)"
  print "  -u, --user          default user owner of files (default admin)"
  print "  -g, --group          default group owner of files (default dba)"
  print "  -x, --exclude        text file that contains a list of excluded files, 1 regular expression per line"
  print "  -?, --help          show help message"
  print
  print " directory            The source directory to add __contents__.xml to"

def main():

  # set default values for parameters
  existHome = os.getenv("EXIST_HOME");
  if not existHome:
    existHome = '/usr/local/eXist'  # last chance backup
  destCollection = '/db'
  default = FileProperties()
  excludeFile = None

  try:
    opts, args = getopt.getopt(sys.argv[1:], "h:c:p:u:g:x:?", ["home=","collection=","permissions=","user=","group=","exclude=","help"])
  except getopt.GetoptError, err:
    print str(err)
    usage()
    sys.exit(1)

  for o, a in opts:
    if o in ("-?", "--help"):
      usage()
      sys.exit(0)
    elif o in ("-h", "--home"):
      existHome = a
    elif o in ("-c","--collection"):
      destCollection = a
    elif o in ("-p","--permissions"):
      default.permissions = a
    elif o in ("-u","--user"):
      default.user = a
    elif o in ("-g","--group"):
      default.group = a
    elif o in ("-x","--exclude"):
      excludeFile = a
    else:
      print "Unknown option ", o
      usage()
      sys.exit(1)
  if (len(args) < 1):
    usage()
    sys.exit(1) 

  srcDirectory = args[0]

  mimeDict = indexMimeTypes(existHome)
  excludeRE = buildExcludeList(excludeFile)

  buildCollection(srcDirectory, destCollection, default, mimeDict, excludeRE)

if __name__ == "__main__":
  main()
