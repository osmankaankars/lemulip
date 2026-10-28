#!/usr/bin/env python3
"""Build a source-pinned, standalone ImageMagick pack on a native Mac.

No system package library is redistributed. All compiled dependencies, original
sources and notices are retained; real format, policy and relocation checks run
before a pack is accepted. Does not create a release or modify an installed app.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import zlib
from urllib.parse import urlsplit

from build_media_engine import assert_host, fetch_source, run, sha256
import bundle_engines

ROOT = Path(__file__).resolve().parent.parent
ORDER = ['jpeg-turbo','libpng','libtiff','webp','lcms2','libxml2','aom','libde265','kvazaar','libheif','imagemagick']
NAMES = set(ORDER)
LICENSES = {'IJG AND BSD-3-Clause AND Zlib','libpng-2.0','libtiff','BSD-3-Clause','MIT','BSD-2-Clause','LGPL-3.0-or-later','ImageMagick'}
REQUIRED_READ = {'PNG','JPEG','WEBP','AVIF','HEIC','TIFF','BMP','GIF','ICO','MSVG'}
REQUIRED_WRITE = REQUIRED_READ - {'MSVG'}
POLICY = '''<?xml version="1.0" encoding="UTF-8"?>
<policymap>
  <policy domain="resource" name="memory" value="256MiB"/>
  <policy domain="resource" name="map" value="512MiB"/>
  <policy domain="resource" name="disk" value="1GiB"/>
  <policy domain="resource" name="width" value="32768"/>
  <policy domain="resource" name="height" value="32768"/>
  <policy domain="resource" name="list-length" value="256"/>
  <policy domain="resource" name="time" value="120"/>
  <policy domain="resource" name="thread" value="4"/>
  <policy domain="delegate" rights="none" pattern="*"/>
  <policy domain="filter" rights="none" pattern="*"/>
  <policy domain="path" rights="none" pattern="@*"/>
  <policy domain="coder" rights="none" pattern="*"/>
  <policy domain="coder" rights="read|write" pattern="{PNG,JPEG,JPG,WEBP,AVIF,HEIC,HEIF,TIFF,TIF,BMP,GIF,ICO,SVG,MSVG}"/>
  <policy domain="coder" rights="write" pattern="INFO"/>
</policymap>
'''


def load_lock(path: Path) -> dict:
    def unique(pairs):
        result = {}
        for k, v in pairs:
            if k in result: raise ValueError('Duplicate lock key')
            result[k] = v
        return result
    lock = json.loads(path.read_text(), object_pairs_hook=unique)
    if not isinstance(lock,dict) or type(lock.get('schema')) is not int or lock['schema'] != 1 or lock.get('minimumMacOS') != '13.0':
        raise ValueError('Unsupported image source lock')
    rows = lock.get('components')
    if not isinstance(rows,list) or [r.get('name') if isinstance(r,dict) else None for r in rows] != ORDER:
        raise ValueError('Image dependency list/order differs')
    for c in rows:
        if not isinstance(c.get('version'),str) or not re.fullmatch(r'[A-Za-z0-9.+_-]{1,80}',c['version']): raise ValueError('Invalid version')
        u = urlsplit(c.get('url',''))
        if u.scheme != 'https' or not u.hostname or u.username or u.password or u.fragment: raise ValueError('Invalid source URL')
        if c.get('license') not in LICENSES: raise ValueError('Unreviewed license')
        if c.get('kind') == 'archive':
            if not re.fullmatch(r'[a-f0-9]{64}',c.get('sha256','')): raise ValueError('Unpinned source archive')
        elif c.get('kind') == 'git':
            if not re.fullmatch(r'[a-f0-9]{40}',c.get('revision','')): raise ValueError('Unpinned source revision')
        else: raise ValueError('Unknown source transport')
    return lock


def configure_arguments(name: str, prefix: Path) -> list[str]:
    common = ['--prefix='+str(prefix),'--disable-shared','--enable-static']
    if name == 'libpng': return common
    if name == 'webp': return common + ['--disable-gl','--disable-sdl','--disable-png','--disable-jpeg','--disable-tiff','--disable-gif','--enable-libwebpmux','--enable-libwebpdemux']
    if name == 'lcms2': return common + ['--without-jpeg','--without-tiff']
    if name == 'libxml2': return common + ['--without-python','--without-http','--without-ftp','--without-lzma','--without-readline']
    if name == 'kvazaar': return common + ['--disable-shared','--disable-asm']
    if name != 'imagemagick': raise ValueError('Unknown configure component')
    return common + ['--disable-installed','--without-modules','--without-perl','--without-magick-plus-plus',
        '--disable-openmp','--disable-opencl','--disable-hdri','--with-quantum-depth=16',
        '--without-x','--without-gslib','--without-rsvg','--without-pango','--without-fontconfig',
        '--without-freetype','--without-djvu','--without-fftw','--without-fpx','--without-gvc',
        '--without-jbig','--without-jxl','--without-lqr','--without-lzma','--without-openexr',
        '--without-openjp2','--without-raqm','--without-raw','--without-wmf','--without-zstd',
        '--with-heic=yes','--with-webp=yes','--with-jpeg=yes','--with-png=yes','--with-tiff=yes',
        '--with-xml=yes','--with-lcms=yes','--with-zlib=yes','--with-bzlib=yes']


def cmake_options(name: str) -> list[str]:
    if name == 'jpeg-turbo': return ['-DENABLE_SHARED=OFF','-DENABLE_STATIC=ON','-DWITH_TURBOJPEG=OFF','-DENABLE_TESTING=OFF']
    if name == 'libtiff': return ['-Dtiff-tools=OFF','-Dtiff-tests=OFF','-Dtiff-contrib=OFF','-Dtiff-docs=OFF','-Dcxx=OFF','-Dlzma=OFF','-Dzstd=OFF','-Dwebp=OFF','-Dlibdeflate=OFF','-Djbig=OFF']
    if name == 'aom': return ['-DENABLE_DOCS=OFF','-DENABLE_TESTS=OFF','-DENABLE_EXAMPLES=OFF','-DENABLE_TOOLS=OFF','-DCONFIG_LIBYUV=0','-DCONFIG_TUNE_VMAF=0']
    if name == 'libde265': return ['-DENABLE_SDL=OFF','-DENABLE_DECODER=OFF','-DENABLE_ENCODER=OFF']
    if name == 'libheif':
        return ['-DENABLE_PLUGIN_LOADING=OFF','-DBUILD_TESTING=OFF','-DWITH_EXAMPLES=OFF','-DWITH_GDK_PIXBUF=OFF',
            '-DWITH_KVAZAAR=ON','-DWITH_KVAZAAR_PLUGIN=OFF','-DWITH_LIBDE265=ON','-DWITH_LIBDE265_PLUGIN=OFF',
            '-DWITH_AOM_ENCODER=ON','-DWITH_AOM_ENCODER_PLUGIN=OFF','-DWITH_AOM_DECODER=ON','-DWITH_AOM_DECODER_PLUGIN=OFF',
            '-DWITH_X265=OFF','-DWITH_X264=OFF','-DWITH_OpenH264_DECODER=OFF','-DWITH_OpenH264_ENCODER=OFF',
            '-DWITH_DAV1D=OFF','-DWITH_RAV1E=OFF','-DWITH_SvtEnc=OFF','-DWITH_FFMPEG_DECODER=OFF',
            '-DWITH_OpenJPEG_DECODER=OFF','-DWITH_OpenJPEG_ENCODER=OFF','-DWITH_JPEG_DECODER=OFF','-DWITH_JPEG_ENCODER=OFF',
            '-DWITH_OPENJPH_ENCODER=OFF','-DWITH_UVG266=OFF','-DWITH_VVENC=OFF','-DWITH_VVDEC=OFF']
    raise ValueError('Unknown CMake component')


def check_formats(listing: str) -> None:
    reads, writes = set(), set()
    for line in listing.splitlines():
        parts = line.split()
        mode = next((p for p in parts[1:3] if re.fullmatch(r'[r-][w-][+\-]', p)), None)
        if mode:
            name = parts[0].rstrip('*')
            if mode[0] == 'r': reads.add(name)
            if mode[1] == 'w': writes.add(name)
    if not REQUIRED_READ <= reads or not REQUIRED_WRITE <= writes:
        raise ValueError('Missing image capabilities: read '+str(sorted(REQUIRED_READ-reads))+' write '+str(sorted(REQUIRED_WRITE-writes)))


def synthetic_png(path: Path) -> None:
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    pixels = b''.join(b'\0'+b''.join(bytes((x*4,y*5,120,255 if x<32 else 128)) for x in range(64)) for y in range(48))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',64,48,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b''))


def scoped_svg_policy(work: Path) -> str:
    # ImageMagick's policy parser does not decode XML entities in path patterns.
    # Build jobs have controlled paths; refuse anything that cannot be represented.
    path=str(work)
    if not work.is_absolute() or any(c in path for c in '&"<>\n\r\t'):
        raise ValueError('Unsafe SVG policy work path')
    pattern=''.join('\\'+c if c in '\\*?[]{}' else c for c in path)
    rules=f"""
  <policy domain="path" rights="none" pattern="*"/>
  <policy domain="path" rights="read|write" pattern="{pattern}/*"/>
  <policy domain="path" rights="write" pattern="-"/>
  <policy domain="path" rights="none" pattern="*../*"/>
  <policy domain="path" rights="none" pattern="@*"/>
  <policy domain="system" name="symlink" rights="none" pattern="follow"/>
  <policy domain="system" name="svg" rights="none" pattern="substitute-entities"/>
  <policy domain="coder" rights="read" pattern="MVG"/>
"""
    return POLICY.replace('</policymap>',rules+'</policymap>')


def smoke_test(pack: Path, work: Path, record: list) -> None:
    work.mkdir(parents=True)
    profile = work/'policy'; profile.mkdir(mode=0o700)
    (profile/'policy.xml').write_text(POLICY)
    env = {'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','HOME':str(work),'LC_ALL':'C',
        'MAGICK_CONFIGURE_PATH':str(profile),'MAGICK_TEMPORARY_PATH':str(profile)}
    magick = str(pack/'bin/magick')
    listing = subprocess.check_output([magick,'-list','format'],env=env,text=True,timeout=30)
    (work/'formats.txt').write_text(listing)
    check_formats(listing)
    original = work/'source.png'; synthetic_png(original); before=sha256(original)
    for extension in ('png','jpg','webp','avif','heic','tiff','bmp','gif','ico'):
        output=work/('output.'+extension)
        run([magick,str(original),'-quality','65',str(output)],work,env,record)
        dimensions=subprocess.check_output([magick,'identify','-format','%w %h',str(output)+'[0]'],env=env,text=True,timeout=30).strip()
        if dimensions != '64 48': raise ValueError('Wrong dimensions after '+extension+': '+dimensions)
        run([magick,str(output)+'[0]',str(work/('decoded-'+extension+'.png'))],work,env,record)
    vector=work/'sample.svg'
    vector.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="48"><rect width="64" height="48" fill="green"/></svg>')
    (profile/'policy.xml').write_text(scoped_svg_policy(work))
    try:
        run([magick,'MSVG:'+str(vector),str(work/'vector.png')],work,env,record)
        outside=work.parent/'outside.png';synthetic_png(outside)
        for argv in ([str(outside),str(work/'forbidden.png')],
                     [str(original),str(work.parent/'forbidden.png')]):
            denied=subprocess.run([magick,*argv],cwd=work,env=env,capture_output=True,timeout=30)
            if denied.returncode==0 or Path(argv[-1]).exists():raise ValueError('SVG job escaped its private file scope')
    finally:
        (profile/'policy.xml').write_text(POLICY)
    for argv in ([str(original),'-resize','32x24',str(work/'resized.png')],
                 [str(original),'-crop','32x24+0+0','+repage',str(work/'cropped.png')],
                 [str(original),'-rotate','90',str(work/'rotated.png')]):
        run([magick,*argv],work,env,record)
    for prohibited in ('https://example.invalid/image.png','MVG:'+str(vector),'@'+str(vector)):
        target=work/'forbidden.png'
        result=subprocess.run([magick,prohibited,str(target)],cwd=work,env=env,capture_output=True,timeout=30)
        if result.returncode == 0 or target.exists(): raise ValueError('Restricted input was accepted')
    if sha256(original) != before: raise ValueError('Original image changed')
    (work/'result.json').write_text(json.dumps({'formats':9,'svg':True,'edits':3,'blockedInputs':3,'originalSHA256':before},indent=2)+'\n')


def source_notices(source: Path) -> list[Path]:
    # Upstreams use several spellings, including libxml2's mixed-case Copyright.
    return sorted(p for p in source.iterdir() if p.is_file() and
                  (p.name.lower().startswith(('copying','copyright','license','licence','notice','patents','authors'))
                   or p.name.lower() == 'readme.ijg'))


def sdk_zlib_metadata(header: str) -> str:
    versions=re.findall(r'^#define[ \t]+ZLIB_VERSION[ \t]+"([0-9]+(?:\.[0-9]+){2,3})"',header,re.M)
    if len(versions)!=1:raise ValueError('Cannot verify the macOS SDK zlib version')
    return 'Name: macOS SDK zlib\nDescription: System zlib, not redistributed\nVersion: '+versions[0]+'\nLibs: -lz\nCflags:\n'


def build(output: Path, work: Path, architecture: str) -> None:
    assert_host(platform.system(),platform.machine(),architecture)
    if output.exists() or output.is_symlink() or work.exists() or work.is_symlink(): raise ValueError('Output and work directories must be new')
    lock=load_lock(ROOT/'script/image-engine-sources.json')
    work.mkdir(parents=True); prefix=work/'prefix'; prefix.mkdir()
    stage=work/'pack'
    for sub in ('bin','sources','licenses'): (stage/sub).mkdir(parents=True,exist_ok=True)
    env={k:os.environ[k] for k in ('PATH','HOME','TMPDIR','DEVELOPER_DIR') if k in os.environ}
    env.update({'MACOSX_DEPLOYMENT_TARGET':'13.0','CC':'clang','CXX':'clang++',
        'CFLAGS':'-O2 -mmacosx-version-min=13.0 -std=gnu17','CXXFLAGS':'-O2 -mmacosx-version-min=13.0',
        'CPPFLAGS':'-I'+str(prefix/'include'),'LDFLAGS':'-L'+str(prefix/'lib')+' -mmacosx-version-min=13.0',
        'PKG_CONFIG_PATH':'','PKG_CONFIG_LIBDIR':str(prefix/'lib/pkgconfig'),
        'GIT_CONFIG_GLOBAL':'/dev/null','GIT_CONFIG_NOSYSTEM':'1','GIT_TERMINAL_PROMPT':'0','LC_ALL':'C','ac_cv_prog_cc_c23':'no'})
    for tool in ('clang','make','cmake','pkg-config','nasm','autoreconf'):
        if not shutil.which(tool,path=env.get('PATH')): raise ValueError('Missing build tool: '+tool)
    pkg=shutil.which('pkg-config',path=env['PATH'])
    wrapper=work/'pkg-config-static';wrapper.write_text('#!/bin/sh\nexec "'+pkg+'" --static "$@"\n');wrapper.chmod(0o755)
    env['PKG_CONFIG']=str(wrapper)
    # macOS supplies zlib but no pkg-config file. Keep discovery isolated while
    # allowing libpng/libtiff to link the SDK library, not a Homebrew substitute.
    sdk=Path(subprocess.check_output(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-path'],env=env,text=True).strip())
    metadata=sdk_zlib_metadata((sdk/'usr/include/zlib.h').read_text())
    pkgdir=prefix/'lib/pkgconfig';pkgdir.mkdir(parents=True,exist_ok=True)
    (pkgdir/'zlib.pc').write_text(metadata)
    jobs=str(min(os.cpu_count() or 2,8));record=[];components=[]
    for component in lock['components']:
        name=component['name']; source,archive=fetch_source(component,work,stage/'sources',env,record)
        notices=source_notices(source)
        if not notices: raise ValueError('No source notices: '+name)
        notice=stage/'licenses'/(name+'.txt')
        with notice.open('wb') as stream:
            stream.write((name+' '+component['version']+'\n'+component['url']+'\n').encode())
            for p in sorted(set(notices)):
                stream.write(('\n===== '+p.name+' =====\n').encode());stream.write(p.read_bytes())
        if name in {'jpeg-turbo','libtiff','aom','libde265','libheif'}:
            builddir=work/(name+'-build')
            args=['cmake','-S',str(source),'-B',str(builddir),'-DCMAKE_BUILD_TYPE=Release',
                '-DCMAKE_INSTALL_PREFIX='+str(prefix),'-DCMAKE_PREFIX_PATH='+str(prefix),
                '-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local','-DBUILD_SHARED_LIBS=OFF',
                '-DCMAKE_POSITION_INDEPENDENT_CODE=ON','-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0',
                '-DCMAKE_OSX_ARCHITECTURES='+architecture,'-DCMAKE_POLICY_VERSION_MINIMUM=3.5',*cmake_options(name)]
            run(args,work,env,record)
            run(['cmake','--build',str(builddir),'--parallel',jobs],work,env,record)
            run(['cmake','--install',str(builddir)],work,env,record)
        else:
            if not (source/'configure').is_file(): run(['autoreconf','-fi'],source,env,record)
            run(['./configure',*configure_arguments(name,prefix)],source,env,record)
            run(['make','-j',jobs],source,env,record);run(['make','install'],source,env,record)
        components.append({'name':name,'license':component['license'],'notice':'licenses/'+notice.name,
            'source':'sources/'+archive.name,'buildInstructions':'sources/BUILD.txt'})
    shutil.copy2(prefix/'bin/magick',stage/'bin/magick')
    for name in ('build_image_engine.py','image-engine-sources.json','build_media_engine.py','bundle_engines.py'):
        shutil.copy2(ROOT/'script'/name,stage/'sources'/name)
    (stage/'sources/BUILD.txt').write_text('Lemulip ImageMagick helper\n'
        'All original input sources and full upstream notices accompany this pack.\n'
        'On a native Mac, install build tools: Xcode Command Line Tools, Python 3.11+, CMake, make, pkgconf, nasm, autoconf, automake and libtool.\n'
        'Place the four included recipe/lock Python and JSON files in a script directory.\n'
        'Run python3 script/build_image_engine.py --arch '+architecture+' --work <new-work> --output <new-pack>.\n'
        'The source lock pins every input. build-record.json records the actual compiler and commands.\n'
        'The original sources include the complete application code needed to rebuild and relink the standalone helper with modified LGPL libraries.\n'
        'No source edits were made. macOS system zlib, bzip2, iconv and C/C++ runtimes are not redistributed.\n'
        'This software is based in part on the work of the Independent JPEG Group.\n'
        'The helper is separate from the MIT Lemulip application.\n')
    smoke_test(stage,work/'smoke',record)
    prefix.rename(work/'hidden-prefix')
    try:
        output.parent.mkdir(parents=True,exist_ok=True)
        # Re-test a relocated standalone executable without any build resources.
        relocated=work/'relocated';(relocated/'bin').mkdir(parents=True)
        shutil.copy2(stage/'bin/magick',relocated/'bin/magick')
        smoke_test(relocated,work/'relocated-smoke',record)
    finally: (work/'hidden-prefix').rename(prefix)
    (stage/'sources/build-record.json').write_text(json.dumps({'architecture':architecture,'minimumMacOS':'13.0',
        'compiler':subprocess.check_output(['clang','--version'],env=env,text=True),'commands':record},indent=2)+'\n')
    manifest={'schema':1,'engine':'imagemagick','version':lock['components'][-1]['version'],'architectures':[architecture],
        'minimumMacOS':'13.0','executables':['bin/magick'],'buildFlags':configure_arguments('imagemagick',prefix),
        'components':components,'files':{p.relative_to(stage).as_posix():sha256(p) for p in sorted(stage.rglob('*')) if p.is_file()}}
    (stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    bundle_engines.validate_pack(stage,{architecture})
    if len(bundle_engines.verify_macho(stage,manifest,{architecture})) != 1: raise ValueError('Unexpected image runtime dependency')
    shutil.copytree(stage,output)
    bundle_engines.validate_pack(output,{architecture});bundle_engines.verify_macho(output,manifest,{architecture})
    print('Verified image pack: '+str(output),flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True);parser.add_argument('--work',type=Path,required=True)
    parser.add_argument('--arch',choices=['arm64','x86_64'],required=True)
    args=parser.parse_args();build(args.output.absolute(),args.work.absolute(),args.arch)

if __name__=='__main__': main()
