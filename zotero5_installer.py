#!/usr/bin/env python

import platform
import glob
import argparse
import re
import urllib2
import json
import os
import sys
from HTMLParser import HTMLParser
import tempfile
import urllib

def zotero_latest():
  response = urllib2.urlopen('https://zotero.org/download/')
  for line in response.read().split('\n'):
    if not '"standaloneVersions"' in line: continue
    line = re.sub(r'.*Downloads,', '', line)
    line = re.sub(r'\),', '', line)
    versions = json.loads(line)
    return versions['standaloneVersions']['linux-' + platform.machine()]

def jurism_latest():
  class Parser(HTMLParser):
    def handle_starttag(self, tag, attrs):
      if tag != 'a': return
      href = [attr[1] for attr in attrs if attr[0] == 'href']
      if len(href) == 0: return
      href = href[0]
      m = re.match(r'https://our.law.nagoya-u.ac.jp/download/client/Jurism-(.+)_linux-' + platform.machine() + '.tar.bz2', href)
      if m is None: return
      self.version = m.group(1)
  response = urllib2.urlopen('https://juris-m.github.io/downloads/')
  parser = Parser()
  parser.feed(response.read())
  return parser.version

class LocationAction(argparse.Action):
  def __call__(self, parser, namespace, values, option_string=None):
    location = values.lower()
    if len(location) == 0:
      parser.error('Missing location')
    elif 'local'[:len(location)] == location:
      setattr(namespace, self.dest, 'local')
    elif 'global'[:len(location)] == location:
      setattr(namespace, self.dest, 'global')
    else:
      parser.error('Unexpected location "' + values + '", expected "local" or "global"')

class ClientAction(argparse.Action):
  def __call__(self, parser, namespace, values, option_string=None):
    client = re.sub(r"[^a-z]", '', values.lower())
    if len(client) == 0:
      parser.error('Missing client')
    elif 'jurism'[:len(client)] == client:
      setattr(namespace, self.dest, 'jurism')
    elif 'zotero'[:len(client)] == client:
      setattr(namespace, self.dest, 'zotero')
    else:
      parser.error('Unexpected client "' + values + '", expected "Zotero" or "Juris-M"')

parser = argparse.ArgumentParser()
parser.add_argument('-c', '--client', action=ClientAction, required=True)
parser.add_argument('-v', '--version')
parser.add_argument('-d', '--destination', action=LocationAction, required=True)
parser.add_argument('-r', '--replace', action='store_true')
parser.add_argument('--cache')

args = parser.parse_args()

if args.cache is not None and not os.path.exists(args.cache):
  print args.cache + ' does not exist'
  sys.exit(1)

if args.version == 'latest' or args.version is None:
  version = zotero_latest() if args.client == 'zotero' else jurism_latest()
  if args.version is None:
    args.version = raw_input(args.client + ' version (' + version + '):')
    if args.version == '': args.version = version
  else:
    args.version = version

if args.destination is None:
  installdir = raw_input('Installation directory: ')
  if installdir == '': raise Exception("Installation directory is mandatory")
  menudir = None
elif args.destination == 'local':
  installdir = os.path.join(os.path.expanduser('~/bin'), args.client)
  menudir = os.path.expanduser('~/.local/share/applications')
else:
  installdir = '/opt'
  menudir = '/usr/share/applications'
  
if os.path.exists(installdir) and not args.replace: raise Exception('Installation directory "' + installdir + '"exists')

if args.client == 'zotero':
  args.url = "https://www.zotero.org/download/client/dl?channel=release&platform=linux-" + platform.machine() + '&version=' + args.version
else:
  args.url = 'https://our.law.nagoya-u.ac.jp/download/client/Jurism-' + args.version + '_linux-' + platform.machine() + '.tar.bz2'

tarball = args.client + '-' + platform.machine() + '-' + args.version + '.tar.bz2'

if args.cache is None:
  tarball = tempfile.NamedTemporaryFile().name
else:
  tarball = args.client + '-' + platform.machine() + '-' + args.version + '.tar.bz2'
  for junk in glob.glob(os.path.join(args.cache, args.client + '-*.tar.bz2')):
    if os.path.basename(junk) != tarball: os.remove(junk)
  tarball = os.path.join(args.cache, tarball)

if os.path.exists(tarball):
  print 'Retaining ' + tarball
else:
  print "Downloading " + args.client + " standalone " + args.version + ' for ' + platform.machine() + ' from ' + args.url
  urllib.urlretrieve (args.url, tarball)

extracted = tempfile.mkdtemp()

def shellquote(s):
  return "'" + s.replace("'", "'\\''") + "'"
os.system('tar --strip 1 -xpf ' + shellquote(tarball) + ' -C ' + shellquote(extracted))

if os.path.exists(installdir): os.system('rm -rf ' + shellquote(installdir))
os.system('mkdir -p ' + shellquote(os.path.dirname(installdir)))
os.system('mv ' + shellquote(extracted) + ' ' + shellquote(installdir))

if not menudir is None:
  if not os.path.exists(menudir): os.system('mkdir -p ' + shellquote(menudir))
  with open(os.path.join(menudir, args.client + '.desktop'), 'w') as desktop:
    desktop.write("[Desktop Entry]\n")
    if args.client == 'zotero':
      desktop.write("Name=Zotero\n")
    else:
      desktop.write("Name=Juris-M\n")
    desktop.write("Comment=Open-source reference manager\n")
    desktop.write("Exec=" + installdir + '/' + args.client + " -datadir profile\n")
    desktop.write("Icon=" + installdir + "/chrome/icons/default/default48.png\n")
    desktop.write("Type=Application\n")
    desktop.write("StartupNotify=true")
