const API = '7.1';

export interface WorkItem {
  id: number;
  fields: Record<string, unknown>;
  relations?: Array<{ rel: string; url: string; attributes: Record<string, unknown> }>;
  _links?: Record<string, { href: string }>;
}

export class AzureDevOpsClient {
  private readonly auth: string;
  private readonly base: string;

  constructor(
    pat: string,
    readonly org: string,
    readonly project?: string,
    readonly team?: string,
  ) {
    this.auth = `Basic ${Buffer.from(`:${pat}`).toString('base64')}`;
    this.base = `https://dev.azure.com/${encodeURIComponent(org)}`;
  }

  private async req<T>(url: string, init: RequestInit = {}): Promise<T> {
    const res = await fetch(url, {
      ...init,
      headers: {
        Authorization: this.auth,
        Accept: 'application/json',
        'Content-Type': 'application/json',
        ...init.headers,
      },
    });
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      throw new Error(`ADO ${res.status} ${res.statusText}: ${body}`);
    }
    return res.json() as Promise<T>;
  }

  private proj(override?: string): string {
    const p = override ?? this.project;
    if (!p) throw new Error('Project is required — set X-ADO-Project header or pass project parameter');
    return encodeURIComponent(p);
  }

  private teamPath(project?: string, team?: string): string {
    return `${this.base}/${this.proj(project)}/${encodeURIComponent(team ?? this.team ?? '')}`;
  }

  // ── Work items ─────────────────────────────────────────────────────────────

  getWorkItem(id: number, fields?: string[]): Promise<WorkItem> {
    const q = new URLSearchParams({ 'api-version': API, '$expand': 'all' });
    if (fields?.length) q.set('fields', fields.join(','));
    return this.req(`${this.base}/_apis/wit/workitems/${id}?${q}`);
  }

  getWorkItems(ids: number[]): Promise<{ value: WorkItem[] }> {
    const q = new URLSearchParams({ 'api-version': API, ids: ids.join(','), '$expand': 'all' });
    return this.req(`${this.base}/_apis/wit/workitems?${q}`);
  }

  createWorkItem(type: string, fields: Record<string, unknown>, project?: string): Promise<WorkItem> {
    const patch = Object.entries(fields).map(([path, value]) => ({
      op: 'add',
      path: path.startsWith('/') ? path : `/fields/${path}`,
      value,
    }));
    const url = `${this.base}/${this.proj(project)}/_apis/wit/workitems/$${encodeURIComponent(type)}?api-version=${API}`;
    return this.req(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json-patch+json' },
      body: JSON.stringify(patch),
    });
  }

  updateWorkItem(id: number, fields: Record<string, unknown>): Promise<WorkItem> {
    const patch = Object.entries(fields).map(([path, value]) => ({
      op: 'add',
      path: path.startsWith('/') ? path : `/fields/${path}`,
      value,
    }));
    return this.req(`${this.base}/_apis/wit/workitems/${id}?api-version=${API}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json-patch+json' },
      body: JSON.stringify(patch),
    });
  }

  async addWorkItemLink(sourceId: number, targetId: number, rel: string): Promise<WorkItem> {
    const target = await this.getWorkItem(targetId);
    const targetUrl = target._links?.self?.href ?? `${this.base}/_apis/wit/workitems/${targetId}`;
    const patch = [{ op: 'add', path: '/relations/-', value: { rel, url: targetUrl, attributes: {} } }];
    return this.req(`${this.base}/_apis/wit/workitems/${sourceId}?api-version=${API}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json-patch+json' },
      body: JSON.stringify(patch),
    });
  }

  // ── Backlog ────────────────────────────────────────────────────────────────

  getBacklog(level?: string, project?: string, team?: string): Promise<unknown> {
    const base = this.teamPath(project, team);
    const suffix = level ? `/${encodeURIComponent(`${project ?? this.project}\\${level}`)}/workitems` : '';
    return this.req(`${base}/_apis/work/backlogs${suffix}?api-version=${API}`);
  }

  // ── Iterations & capacity ─────────────────────────────────────────────────

  listTeamIterations(timeframe?: string, project?: string, team?: string): Promise<unknown> {
    const q = new URLSearchParams({ 'api-version': API });
    if (timeframe) q.set('$timeframe', timeframe);
    return this.req(`${this.teamPath(project, team)}/_apis/work/teamsettings/iterations?${q}`);
  }

  getTeamCapacity(iterationId: string, project?: string, team?: string): Promise<unknown> {
    return this.req(
      `${this.teamPath(project, team)}/_apis/work/teamsettings/iterations/${iterationId}/capacities?api-version=${API}`
    );
  }

  // ── Wiki ──────────────────────────────────────────────────────────────────

  listWikis(project?: string): Promise<unknown> {
    return this.req(`${this.base}/${this.proj(project)}/_apis/wiki/wikis?api-version=${API}`);
  }

  getWikiPage(wikiId: string, path: string, project?: string): Promise<unknown> {
    const q = new URLSearchParams({ 'api-version': API, path, includeContent: 'true' });
    return this.req(`${this.base}/${this.proj(project)}/_apis/wiki/wikis/${wikiId}/pages?${q}`);
  }

  // ── Git ───────────────────────────────────────────────────────────────────

  listRepositories(project?: string): Promise<unknown> {
    return this.req(`${this.base}/${this.proj(project)}/_apis/git/repositories?api-version=${API}`);
  }

  getRepository(repoId: string, project?: string): Promise<unknown> {
    return this.req(`${this.base}/${this.proj(project)}/_apis/git/repositories/${repoId}?api-version=${API}`);
  }

  getFile(repoId: string, path: string, ref?: string, project?: string): Promise<unknown> {
    const q = new URLSearchParams({ 'api-version': API, path });
    if (ref) q.set('versionDescriptor.version', ref);
    return this.req(`${this.base}/${this.proj(project)}/_apis/git/repositories/${repoId}/items?${q}`);
  }
}
