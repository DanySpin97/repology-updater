-- Copyright (C) 2016-2020 Dmitry Marakasov <amdmi3@amdmi3.ru>
--
-- This file is part of repology
--
-- repology is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- repology is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with repology.  If not, see <http://www.gnu.org/licenses/>.

--------------------------------------------------------------------------------
-- Update aggregate tables: maintainers, pass1
--------------------------------------------------------------------------------
UPDATE maintainers
SET
	num_packages = tmp.num_packages,
	num_packages_newest = tmp.num_packages_newest,
	num_packages_outdated = tmp.num_packages_outdated,
	num_packages_ignored = tmp.num_packages_ignored,
	num_packages_unique = tmp.num_packages_unique,
	num_packages_devel = tmp.num_packages_devel,
	num_packages_legacy = tmp.num_packages_legacy,
	num_packages_incorrect = tmp.num_packages_incorrect,
	num_packages_untrusted = tmp.num_packages_untrusted,
	num_packages_noscheme = tmp.num_packages_noscheme,
	num_packages_rolling = tmp.num_packages_rolling,

	num_projects = tmp.num_projects,
	num_projects_newest = tmp.num_projects_newest,
	num_projects_outdated = tmp.num_projects_outdated,
	num_projects_problematic = tmp.num_projects_problematic,

	last_seen = now(),
	orphaned_at = NULL
FROM (
	SELECT
		unnest(maintainers) AS maintainer,

		count(*) AS num_packages,
		count(*) FILTER (WHERE versionclass = 1) AS num_packages_newest,
		count(*) FILTER (WHERE versionclass = 2) AS num_packages_outdated,
		count(*) FILTER (WHERE versionclass = 3) AS num_packages_ignored,
		count(*) FILTER (WHERE versionclass = 4) AS num_packages_unique,
		count(*) FILTER (WHERE versionclass = 5) AS num_packages_devel,
		count(*) FILTER (WHERE versionclass = 6) AS num_packages_legacy,
		count(*) FILTER (WHERE versionclass = 7) AS num_packages_incorrect,
		count(*) FILTER (WHERE versionclass = 8) AS num_packages_untrusted,
		count(*) FILTER (WHERE versionclass = 9) AS num_packages_noscheme,
		count(*) FILTER (WHERE versionclass = 10) AS num_packages_rolling,

		count(DISTINCT effname) AS num_projects,
		count(DISTINCT effname) FILTER(WHERE versionclass = 1 OR versionclass = 4 OR versionclass = 5) AS num_projects_newest,
		count(DISTINCT effname) FILTER(WHERE versionclass = 2) AS num_projects_outdated,
		count(DISTINCT effname) FILTER(WHERE versionclass = 3 OR versionclass = 7 OR versionclass = 8) AS num_projects_problematic
	FROM packages
	GROUP BY maintainer
) AS tmp
WHERE maintainers.maintainer = tmp.maintainer;

--------------------------------------------------------------------------------
-- Update aggregate tables: maintainers, pass2, depends on repositories
--------------------------------------------------------------------------------
UPDATE maintainers
SET
	num_packages_per_repo = tmp.num_packages_per_repo,
	num_projects_per_repo = tmp.num_projects_per_repo,
	num_projects_newest_per_repo = tmp.num_projects_newest_per_repo,
	num_projects_outdated_per_repo = tmp.num_projects_outdated_per_repo,
	num_projects_problematic_per_repo = tmp.num_projects_problematic_per_repo,
	bestrepo = tmp.bestrepo,
	bestrepo_num_projects = tmp.bestrepo_num_projects,
	bestrepo_num_projects_newest = tmp.bestrepo_num_projects_newest,
	bestrepo_num_projects_outdated = tmp.bestrepo_num_projects_outdated,
	bestrepo_num_projects_problematic = tmp.bestrepo_num_projects_problematic,
	num_repos = tmp.num_repos
FROM (
	SELECT
		maintainer,
		json_object_agg(repo, num_packages) AS num_packages_per_repo,
		json_object_agg(repo, num_projects) AS num_projects_per_repo,
		json_object_agg(repo, num_projects_newest) AS num_projects_newest_per_repo,
		json_object_agg(repo, num_projects_outdated) AS num_projects_outdated_per_repo,
		json_object_agg(repo, num_projects_problematic) AS num_projects_problematic_per_repo,
		min(bestrepo) AS bestrepo,
		min(bestrepo_num_projects) AS bestrepo_num_projects,
		min(bestrepo_num_projects_newest) AS bestrepo_num_projects_newest,
		min(bestrepo_num_projects_outdated) AS bestrepo_num_projects_outdated,
		min(bestrepo_num_projects_problematic) AS bestrepo_num_projects_problematic,
		count(DISTINCT repo) AS num_repos
	FROM (
		SELECT
			*,
			first_value(repo) OVER (PARTITION BY maintainer ORDER BY num_projects_newest DESC, num_projects_outdated, repository_weight DESC) AS bestrepo,
			first_value(num_projects) OVER (PARTITION BY maintainer ORDER BY num_projects_newest DESC, num_projects_outdated, repository_weight DESC) AS bestrepo_num_projects,
			first_value(num_projects_newest) OVER (PARTITION BY maintainer ORDER BY num_projects_newest DESC, num_projects_outdated, repository_weight DESC) AS bestrepo_num_projects_newest,
			first_value(num_projects_outdated) OVER (PARTITION BY maintainer ORDER BY num_projects_newest DESC, num_projects_outdated, repository_weight DESC) AS bestrepo_num_projects_outdated,
			first_value(num_projects_problematic) OVER (PARTITION BY maintainer ORDER BY num_projects_newest DESC, num_projects_outdated, repository_weight DESC) AS bestrepo_num_projects_problematic
		FROM (
			SELECT
				unnest(maintainers) AS maintainer,
				repo,
				min(repositories.num_metapackages_newest) AS repository_weight,
				count(*) AS num_packages,
				count(DISTINCT effname) AS num_projects,
				count(DISTINCT effname) FILTER (WHERE versionclass = 1 OR versionclass = 4 OR versionclass = 5) AS num_projects_newest,
				count(DISTINCT effname) FILTER (WHERE versionclass = 2) AS num_projects_outdated,
				count(DISTINCT effname) FILTER (WHERE versionclass = 3 OR versionclass = 7 OR versionclass = 8) AS num_projects_problematic
			FROM packages INNER JOIN repositories ON (packages.repo = repositories.name)
			GROUP BY maintainer, repo
		) AS maintainer_repos
	) AS maintainer_repos_with_bestrepo
	GROUP BY maintainer
) AS tmp
WHERE maintainers.maintainer = tmp.maintainer;

--------------------------------------------------------------------------------
-- Update aggregate tables: maintainers, pass3
--------------------------------------------------------------------------------
UPDATE maintainers
SET
	num_projects_per_category = tmp.num_projects_per_category
FROM (
	SELECT
		maintainer,
		json_object_agg(category, numcatmetapkg) AS num_projects_per_category
	FROM (
		SELECT
			unnest(maintainers) AS maintainer,
			category,
			count(DISTINCT effname) AS numcatmetapkg
		FROM packages
		WHERE category IS NOT NULL
		GROUP BY maintainer, category
	) AS sub
	GROUP BY maintainer
) AS tmp
WHERE maintainers.maintainer = tmp.maintainer;

--------------------------------------------------------------------------------
-- Update aggregate tables: maintainers, finalize
--------------------------------------------------------------------------------
UPDATE maintainers
SET
	num_packages = 0,
	num_packages_newest = 0,
	num_packages_outdated = 0,
	num_packages_ignored = 0,
	num_packages_unique = 0,
	num_packages_devel = 0,
	num_packages_legacy = 0,
	num_packages_incorrect = 0,
	num_packages_untrusted = 0,
	num_packages_noscheme = 0,
	num_packages_rolling = 0,

	num_projects = 0,
	num_projects_newest = 0,
	num_projects_outdated = 0,
	num_projects_problematic = 0,

	num_packages_per_repo = '{}',

	num_projects_per_repo = '{}',
	num_projects_newest_per_repo = '{}',
	num_projects_outdated_per_repo = '{}',
	num_projects_problematic_per_repo = '{}',

	bestrepo = NULL,
	bestrepo_num_projects = 0,
	bestrepo_num_projects_newest = 0,
	bestrepo_num_projects_outdated = 0,
	bestrepo_num_projects_problematic = 0,

	num_projects_per_category = '{}',

	num_repos = 0,

	orphaned_at = coalesce(orphaned_at, now())
WHERE
	last_seen != now();

ANALYZE maintainers;
