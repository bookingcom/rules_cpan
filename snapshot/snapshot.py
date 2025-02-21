#!/usr/bin/env python
import argparse
import concurrent.futures
import hashlib
import io
import json
import logging
import os
import sys
import tarfile
import urllib
import zipfile
from collections import OrderedDict, defaultdict
from functools import partial
from multiprocessing import Pool, TimeoutError
from re import compile
from typing import Dict

import filetype
import requests
import yaml
from xdg_base_dirs import xdg_cache_home

REQUIRES = compile(r'''requires\s+['"]([^\s]+)['"](,\s*['"]([^'"]+)['"])?\s*;\s*$''')

logger = logging.getLogger(__name__)


def prettify(d, indent=0):
    '''
    Print the file tree structure with proper indentation.
    '''
    for key, value in d.items():
        if type(value) is list:
            if value:
                print('  ' * indent + str(value))
        else:
            print('  ' * indent + str(key))
            if isinstance(value, dict):
                prettify(value, indent+1)
            else:
                print('  ' * (indent+1) + str(value))

class Processor:
    def __init__(self,
                 metacpan_url: str = None,
                 cache_directory: str = None,
                 cpanfile: io.TextIOBase = None,
                 jobs: int = 0,
                 core_modules: io.TextIOBase = None,
                 perl_version: str = None
                 ):
        self.metacpan_url = metacpan_url
        self.cache_directory = cache_directory
        self.jobs = jobs
        self.core_modules = core_modules

        self.core_modules = self.parse_core_modules(core_modules)
        self.dependencies = self.parse_cpanfile(cpanfile)
        self.members_per_package = {}

        if perl_version:
            if perl_version not in self.core_modules:
                raise ValueError(f"Perl version {perl_version} not found in core modules")
            self.perl_version = perl_version
        else:
            self.perl_version = max(self.core_modules.keys())

        logger.info(f"Using perl version {self.perl_version}")

    def parse_cpanfile(self, cpanfile: io.TextIOBase) -> Dict[str, str]:
        out = {}
        for line in cpanfile.readlines():
            if REQUIRES.match(line):
                package, _, version_spec = REQUIRES.match(line).groups()
                out[package] = version_spec
        return out

    def parse_core_modules(self, core_modules: io.TextIOBase) -> Dict[str, Dict[str, str]]:
        out = json.load(core_modules)
        return out

    def populate_paths_per_package(self, package, files):
        def attach(branch, trunk):
            if '/' not in branch:
                trunk[branch] = defaultdict(dict, list())
                return

            parts = branch.split('/', 1)
            if len(parts) == 1:
                trunk[parts[0]].append(parts[1])
                return

            node, others = parts
            if node not in trunk:
                trunk[node] = defaultdict(dict, list())
            attach(others, trunk[node])

        self.members_per_package[package] = defaultdict(dict, list())
        for member in files:
            attach(member, self.members_per_package[package])

    def _read_package_meta_tar(self, package, archive):
        def extractfile(member, extract):
            try:
                content = tar.extractfile(member).read().decode()
                return extract(content)
            except (UnicodeDecodeError, json.decoder.JSONDecodeError, yaml.YAMLError) as e:
                logger.error(f"Failed to decode {member.name} in {archive}")
                return None

        try:
            tar = tarfile.open(archive)
            self.populate_paths_per_package(package, tar.getnames())
            for member in tar.getmembers():
                if member.name.endswith('/META.json'):
                    content = extractfile(member, json.loads)
                    if content:
                        return content
                if member.name.endswith('/META.yml'):
                    content = extractfile(member, yaml.safe_load)
                    if content:
                        return content
        except tarfile.ReadError:
            logger.exception(f"Failed to read {archive}")

        return None

    def _read_package_meta_zip(self, package, archive):
        def extractfile(zip, member, extract):
            try:
                content = zip.open(member).read().decode()
                return extract(content)
            except (UnicodeDecodeError, json.decoder.JSONDecodeError, yaml.YAMLError) as e:
                logger.error(f"Failed to decode {member.name} in {archive}")
                return None

        try:
            zip = zipfile.ZipFile(archive, 'r')
            self.populate_paths_per_package(package, zip.namelist())
            for member in zip.namelist():
                if member.endswith('/META.json'):
                    content = extractfile(zip, member, json.loads)
                    if content:
                        return content
                if member.endswith('/META.yml'):
                    content = extractfile(zip, member, yaml.safe_load)
                    if content:
                        return content
        except tarfile.ReadError:
            logger.exception(f"Failed to read {archive}")

        return None

    def _read_package_meta(self, package, archive):
        kind = filetype.guess(archive)
        if kind is None:
            raise RuntimeError(f"Failed to guess type of {archive}")

        if kind.mime in ['application/x-tar', 'application/gzip']:
            return self._read_package_meta_tar(package, archive)

        if kind.mime == "application/zip":
            return self._read_package_meta_zip(package, archive)

        raise RuntimeError(f"Unsupported file type {kind.mime} for {archive}")

    def get_package_meta(self, package, archive):
        meta = self._read_package_meta(package, archive) or {}

        download_url_meta = json.loads(open(archive + ".meta").read())

        core_package = self.core_modules[self.perl_version].get(package, None)
        if core_package and str(core_package) >= str(meta.get('version', download_url_meta.get('version', None))):
            logger.warning(f"Found {package} in core modules with version {core_package}, from meta {meta['version']}")
            return {
                "name": package,
                "version": core_package,
                "download_url": None,
                "requires": [],
                "dynamic_config": False,
                "is_core": True,
            }

        if not meta:
            logger.warning(f"Failed to find META.json or META.yml in {archive}")

        if meta.get('dynamic_config', 0):
            logger.warning(f"Package {package} has dynamic_config")

        requires = meta.get('requires', meta.get('prereqs', {}).get('runtime', {}).get('requires', None)) or []

        is_test = package.startswith("Test::")

        def cleanup_test_deps(deps):
            for dep in deps:
                if dep.startswith("Test::"):
                    if is_test:
                        yield dep
                    continue
                yield dep

        files = self.members_per_package.get(package, {})
        if not files:
            logger.warning(f"Failed to find files for {package} in {archive}")
            logger.warning(self.members_per_package.keys())

        return {
            "name": package,
            "version": meta.get('version', download_url_meta.get('version', None)),
            "requires": sorted(list(cleanup_test_deps(requires))),
            "conflicts": meta.get('conflicts', []),
            "is_core": False,
            "url": download_url_meta["download_url"],
            "release": download_url_meta["release"] if download_url_meta["release"] in files else sorted(files.keys())[0],
            "sha256": download_url_meta["checksum_sha256"],
        }

    def get_package_meta_after_download(self, config, **kw):
        package, version_spec = config
        cache_file = os.path.join(self.cache_directory, f"{package.replace("::", "-")}.tar.gz")
        if os.path.exists(cache_file) and os.path.exists(cache_file + ".meta"):
            return self.get_package_meta(package, cache_file)

        logger.info(f"Checking {package} {version_spec}")

        if version_spec:
            version_spec = f"?version={urllib.parse.quote(version_spec)}"

        version_spec = version_spec or ""

        url = f"{self.metacpan_url}/v1/download_url/{package}{version_spec}"

        logger.debug(f"Requesting download url for {package} {url}")

        with requests.get(url) as download_url:
            if download_url.status_code != requests.codes.ok:
                if self.core_modules[self.perl_version].get(package, None):
                    with open(cache_file + ".meta", "w") as f:
                        f.write(json.dumps({
                            "name": package,
                            "version": self.core_modules[self.perl_version][package],
                            "requires": [],
                            "conflicts": [],
                            "is_core": True,
                            "url": None,
                        }))
                    logger.info(f"Found {package} in core modules")
                    return {
                        "name": package,
                        "version": self.core_modules[self.perl_version][package],
                        "requires": [],
                        "conflicts": [],
                        "is_core": True,
                        "url": None,
                    }
                logger.error(f"Failed to find {package} {version_spec}")
                return {
                    "name": package,
                    "is_failure": True
                }
            url = download_url.json()['download_url']
            checksum_sha256 = download_url.json()['checksum_sha256']
            meta = download_url.json()

        logger.debug(f"Downloading {package} from {url}")

        sha256 = hashlib.sha256()

        with requests.get(url, stream=True) as r:
            r.raise_for_status()
            with open(cache_file, 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
                    sha256.update(chunk)

        if sha256.hexdigest() != checksum_sha256:
            raise RuntimeError(f"Checksum mismatch for {package} {version_spec} {url} expected {checksum_sha256} got {sha256.hexdigest()}")

        open(cache_file + ".meta", "w").write(json.dumps(meta))

        return self.get_package_meta(package, cache_file)

    def process(self):
        logger.info(f"Running with {self.jobs} jobs")
        logger.info(f"Found {len(self.dependencies)} dependencies")
        logger.debug(f"Dependencies: {self.dependencies}")

        logger.debug(f"Cache directory: {self.cache_directory}")

        pending = set(self.dependencies.items())

        os.makedirs(self.cache_directory, exist_ok=True)

        resolved = dict()
        failures = set()

        with concurrent.futures.ProcessPoolExecutor(max_workers=self.jobs) as executor:
            while pending:
                logger.debug(f"Resolving pending: {pending}")
                futures = executor.map(self.get_package_meta_after_download, pending)
                pending.clear()
                for result in futures:
                    if result.get('is_failure', False):
                        failures.add(result['name'])
                        continue

                    resolved[result['name']] = result
                    for dep in result['requires']:
                        if dep not in resolved:
                            pending.add((dep, None))

        resolved.pop("perl", None)

        if failures:
            logger.error(f"Failed to resolve {len(failures)} dependencies: {sorted(failures)}")

        keys = []
        pure_core = []
        for key, value in resolved.items():
            if not value['is_core']:
                keys.append(key)
            else:
                pure_core.append(key)

        for key in pure_core:
            resolved.pop(key)

        requested = OrderedDict()
        for key, value in self.dependencies.items():
            requested[key] = value

        out = OrderedDict({
            "failures": sorted(failures),
            "requested": requested,
            "resolved": OrderedDict(),
        })

        for name in sorted(resolved.keys()):
            values = resolved[name]
            out["resolved"][name.replace("::", "-")] = OrderedDict({
                "release": values['release'],
                "dependencies": sorted([x for x in values['requires'] if x in resolved]),
                "url": values['url'],
                "sha256": values['sha256']
            })

        return out


def _parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cpanfile', '-c', type=argparse.FileType('r'), default='cpanfile')
    parser.add_argument('--log-level', '-l', type=str, default='INFO')
    parser.add_argument('--cache-directory', type=str, default=os.path.join(xdg_cache_home(), 'rules-cpan-snapshot'))
    parser.add_argument('--jobs', '-j', type=int, default=len(os.sched_getaffinity(0)), help="Number of parallel jobs to run")
    parser.add_argument('--metacpan-url', '-u', type=str, default='https://fastapi.metacpan.org/')
    parser.add_argument('--core-modules', '-m', type=argparse.FileType('r'), default=os.getenv('CORE_MODULES', None))
    parser.add_argument('--perl-version', '-p', type=str, help='Perl version to use for core modules, will default to the latest')
    parser.add_argument('--output', '-o', type=argparse.FileType('w'), default=sys.stdout)
    return parser.parse_args()


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)

    if os.getenv('CORE_MODULES', None):
        os.environ['CORE_MODULES'] = os.path.abspath(os.getenv('CORE_MODULES'))

    if os.getenv('BUILD_WORKING_DIRECTORY', None):
        os.chdir(os.getenv('BUILD_WORKING_DIRECTORY'))

    args = _parse_args()

    logger.setLevel(getattr(logging, args.log_level))

    processor = Processor(
        metacpan_url=args.metacpan_url,
        cache_directory=args.cache_directory,
        cpanfile=args.cpanfile,
        jobs=args.jobs,
        core_modules=args.core_modules
    )

    data = processor.process()

    json.dump(data, args.output, indent=2)
