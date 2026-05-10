import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import type { AzureDevOpsClient } from './ado/client.js';

const json = (data: unknown) => ({
  content: [{ type: 'text' as const, text: JSON.stringify(data, null, 2) }],
});

export function createServer(ado: AzureDevOpsClient): McpServer {
  const server = new McpServer({ name: 'azure-devops', version: '1.0.0' });

  server.tool(
    'wit_work_item',
    'Read one or more Azure DevOps work items by ID.',
    {
      id: z.number().optional().describe('Single work item ID'),
      ids: z.array(z.number()).optional().describe('Multiple work item IDs'),
      fields: z.array(z.string()).optional().describe('Specific fields to return (omit for all)'),
    },
    async ({ id, ids, fields }) => {
      if (ids?.length) return json(await ado.getWorkItems(ids));
      if (id != null) return json(await ado.getWorkItem(id, fields));
      throw new Error('Provide id or ids');
    }
  );

  server.tool(
    'wit_work_item_write',
    'Create or update an Azure DevOps work item.',
    {
      type: z.string().optional().describe('Work item type — Epic, Feature, User Story, Task, Bug. Required for create.'),
      id: z.number().optional().describe('Work item ID. Required for update.'),
      project: z.string().optional().describe('Project override'),
      fields: z.record(z.unknown()).describe(
        'Field name → value map. Use full field reference names, e.g. "System.Title", "Microsoft.VSTS.Common.AcceptanceCriteria".'
      ),
    },
    async ({ type, id, project, fields }) => {
      if (id != null) return json(await ado.updateWorkItem(id, fields));
      if (type) return json(await ado.createWorkItem(type, fields, project));
      throw new Error('Provide id (update) or type (create)');
    }
  );

  server.tool(
    'wit_work_item_link_write',
    'Add a link between two Azure DevOps work items.',
    {
      sourceId: z.number().describe('Work item that receives the link'),
      targetId: z.number().describe('Work item to link to'),
      linkType: z.string()
        .default('System.LinkTypes.Hierarchy-Reverse')
        .describe('Relation type name. Hierarchy-Reverse sets targetId as parent of sourceId.'),
    },
    async ({ sourceId, targetId, linkType }) =>
      json(await ado.addWorkItemLink(sourceId, targetId, linkType))
  );

  server.tool(
    'wit_backlog',
    'Get backlog work items for a team.',
    {
      level: z.string().optional().describe('Backlog level — Epics, Features, Stories'),
      project: z.string().optional(),
      team: z.string().optional(),
    },
    async ({ level, project, team }) => json(await ado.getBacklog(level, project, team))
  );

  server.tool(
    'work_list_team_iterations',
    'List sprints/iterations for a team.',
    {
      timeframe: z.enum(['current', 'past', 'future']).optional(),
      project: z.string().optional(),
      team: z.string().optional(),
    },
    async ({ timeframe, project, team }) =>
      json(await ado.listTeamIterations(timeframe, project, team))
  );

  server.tool(
    'work_get_team_capacity',
    'Get team member capacity for a sprint.',
    {
      iterationId: z.string().describe('Iteration GUID or path'),
      project: z.string().optional(),
      team: z.string().optional(),
    },
    async ({ iterationId, project, team }) =>
      json(await ado.getTeamCapacity(iterationId, project, team))
  );

  server.tool(
    'wiki',
    'List wikis or read a wiki page.',
    {
      action: z.enum(['list', 'get']).default('list'),
      wikiId: z.string().optional().describe('Wiki identifier (required for action=get)'),
      path: z.string().optional().describe('Page path (required for action=get)'),
      project: z.string().optional(),
    },
    async ({ action, wikiId, path, project }) => {
      if (action === 'list') return json(await ado.listWikis(project));
      if (!wikiId || !path) throw new Error('wikiId and path required for action=get');
      return json(await ado.getWikiPage(wikiId, path, project));
    }
  );

  server.tool(
    'wiki_upsert_page',
    'Create or update a wiki page. Performs a GET to obtain the ETag then PUTs the new content.',
    {
      wikiId: z.string().describe('Wiki identifier'),
      path: z.string().describe('Page path, e.g. /Architecture/ADRs/ADR-001-title'),
      content: z.string().describe('Full Markdown content for the page'),
      project: z.string().optional(),
    },
    async ({ wikiId, path, content, project }) =>
      json(await ado.upsertWikiPage(wikiId, path, content, project))
  );

  server.tool(
    'repo_repository',
    'List or get Git repositories in the project.',
    {
      repository: z.string().optional().describe('Repository name or ID. Omit to list all.'),
      project: z.string().optional(),
    },
    async ({ repository, project }) => {
      if (repository) return json(await ado.getRepository(repository, project));
      return json(await ado.listRepositories(project));
    }
  );

  server.tool(
    'repo_file',
    'Read a file from an Azure DevOps Git repository.',
    {
      repository: z.string().describe('Repository name or ID'),
      path: z.string().describe('File path, e.g. /src/main.ts'),
      ref: z.string().optional().describe('Branch or commit SHA (defaults to default branch)'),
      project: z.string().optional(),
    },
    async ({ repository, path, ref, project }) =>
      json(await ado.getFile(repository, path, ref, project))
  );

  return server;
}
