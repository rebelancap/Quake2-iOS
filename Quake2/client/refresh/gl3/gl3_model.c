/*
 * Copyright (C) 1997-2001 Id Software, Inc.
 * Copyright (C) 2016-2017 Daniel Gibson
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 *
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
 * 02111-1307, USA.
 *
 * =======================================================================
 *
 * Model loading and caching for OpenGL3. Includes the .bsp file format
 *
 * =======================================================================
 */

#include "header/local.h"

enum { MAX_MOD_KNOWN = 512 };

static gl3model_t *loadmodel;
static byte mod_novis[MAX_MAP_LEAFS / 8];
gl3model_t mod_known[MAX_MOD_KNOWN];
static int mod_numknown;
int registration_sequence;
static byte *mod_base;

/* the inline * models from the current map are kept seperate */
gl3model_t mod_inline[MAX_MOD_KNOWN];

mleaf_t *
GL3_Mod_PointInLeaf(vec3_t p, gl3model_t *model)
{
	mnode_t *node;
	float d;
	cplane_t *plane;

	if (!model || !model->nodes)
	{
		ri.Sys_Error(ERR_DROP, "Mod_PointInLeaf: bad model");
	}

	node = model->nodes;

	while (1)
	{
		if (node->contents != -1)
		{
			return (mleaf_t *)node;
		}

		plane = node->plane;
		d = DotProduct(p, plane->normal) - plane->dist;

		if (d > 0)
		{
			node = node->children[0];
		}
		else
		{
			node = node->children[1];
		}
	}

	return NULL; /* never reached */
}

byte*
GL3_Mod_ClusterPVS(int cluster, gl3model_t *model)
{
	if ((cluster == -1) || !model->vis)
	{
		return mod_novis;
	}

	return Mod_DecompressVis((byte *)model->vis +
			model->vis->bitofs[cluster][DVIS_PVS],
			(model->vis->numclusters + 7) >> 3);
}

void
GL3_Mod_Modellist_f(void)
{
	int i;
	gl3model_t *mod;
	int total;

	total = 0;
	R_Printf(PRINT_ALL, "Loaded models:\n");

	for (i = 0, mod = mod_known; i < mod_numknown; i++, mod++)
	{
		if (!mod->name[0])
		{
			continue;
		}

		R_Printf(PRINT_ALL, "%8i : %s\n", mod->extradatasize, mod->name);
		total += mod->extradatasize;
	}

	R_Printf(PRINT_ALL, "Total resident: %i\n", total);
}

void
GL3_Mod_Init(void)
{
	memset(mod_novis, 0xff, sizeof(mod_novis));
}

static void
Mod_LoadLighting(lump_t *l)
{
	if (!l->filelen)
	{
		loadmodel->lightdata = NULL;
		return;
	}

	loadmodel->lightdata = Hunk_Alloc(l->filelen);
	memcpy(loadmodel->lightdata, mod_base + l->fileofs, l->filelen);
}

static void
Mod_LoadVisibility(lump_t *l)
{
	int i;

	if (!l->filelen)
	{
		loadmodel->vis = NULL;
		return;
	}

	loadmodel->vis = Hunk_Alloc(l->filelen);
	memcpy(loadmodel->vis, mod_base + l->fileofs, l->filelen);

	loadmodel->vis->numclusters = LittleLong(loadmodel->vis->numclusters);

	for (i = 0; i < loadmodel->vis->numclusters; i++)
	{
		loadmodel->vis->bitofs[i][0] = LittleLong(loadmodel->vis->bitofs[i][0]);
		loadmodel->vis->bitofs[i][1] = LittleLong(loadmodel->vis->bitofs[i][1]);
	}
}

static void
Mod_LoadVertexes(lump_t *l)
{
	dvertex_t *in;
	mvertex_t *out;
	int i, count;

	in = (void *)(mod_base + l->fileofs);

	if (l->filelen % sizeof(*in))
	{
		ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: funny lump size in %s",
				loadmodel->name);
	}

	count = l->filelen / sizeof(*in);
	out = Hunk_Alloc(count * sizeof(*out));

	loadmodel->vertexes = out;
	loadmodel->numvertexes = count;

	for (i = 0; i < count; i++, in++, out++)
	{
		out->position[0] = LittleFloat(in->point[0]);
		out->position[1] = LittleFloat(in->point[1]);
		out->position[2] = LittleFloat(in->point[2]);
	}
}

static void
Mod_LoadSubmodels(lump_t *l)
{
	dmodel_t *in;
	mmodel_t *out;
	int i, j, count;

	in = (void *)(mod_base + l->fileofs);

	if (l->filelen % sizeof(*in))
	{
		ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: funny lump size in %s",
				loadmodel->name);
	}

	count = l->filelen / sizeof(*in);
	out = Hunk_Alloc(count * sizeof(*out));

	loadmodel->submodels = out;
	loadmodel->numsubmodels = count;

	for (i = 0; i < count; i++, in++, out++)
	{
		for (j = 0; j < 3; j++)
		{
			/* spread the mins / maxs by a pixel */
			out->mins[j] = LittleFloat(in->mins[j]) - 1;
			out->maxs[j] = LittleFloat(in->maxs[j]) + 1;
			out->origin[j] = LittleFloat(in->origin[j]);
		}

		out->radius = Mod_RadiusFromBounds(out->mins, out->maxs);
		out->headnode = LittleLong(in->headnode);
		out->firstface = LittleLong(in->firstface);
		out->numfaces = LittleLong(in->numfaces);
	}
}

static void
Mod_LoadEdges(lump_t *l)
{
	dedge_t *in;
	medge_t *out;
	int i, count;

	in = (void *)(mod_base + l->fileofs);

	if (l->filelen % sizeof(*in))
	{
		ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: funny lump size in %s",
				loadmodel->name);
	}

	count = l->filelen / sizeof(*in);
	out = Hunk_Alloc((count + 1) * sizeof(*out));

	loadmodel->edges = out;
	loadmodel->numedges = count;

	for (i = 0; i < count; i++, in++, out++)
	{
		out->v[0] = (unsigned short)LittleShort(in->v[0]);
		out->v[1] = (unsigned short)LittleShort(in->v[1]);
	}
}

static void
Mod_LoadTexinfo(lump_t *l)
{
	texinfo_t *in;
	mtexinfo_t *out, *step;
	int i, j, count;
	char name[MAX_QPATH];
	int next;

	in = (void *)(mod_base + l->fileofs);

	if (l->filelen % sizeof(*in))
	{
		ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: funny lump size in %s",
				loadmodel->name);
	}

	count = l->filelen / sizeof(*in);
	out = Hunk_Alloc(count * sizeof(*out));

	loadmodel->texinfo = out;
	loadmodel->numtexinfo = count;

	for (i = 0; i < count; i++, in++, out++)
	{
		for (j = 0; j < 4; j++)
		{
			out->vecs[0][j] = LittleFloat(in->vecs[0][j]);
			out->vecs[1][j] = LittleFloat(in->vecs[1][j]);
		}

		out->flags = LittleLong(in->flags);
		next = LittleLong(in->nexttexinfo);

		if (next > 0)
		{
			out->next = loadmodel->texinfo + next;
		}
		else
		{
			out->next = NULL;
		}

		Com_sprintf(name, sizeof(name), "textures/%s.wal", in->texture);

		out->image = GL3_FindImage(name, it_wall);

		if (!out->image)
		{
			R_Printf(PRINT_ALL, "Couldn't load %s\n", name);
			out->image = gl3_notexture;
		}
	}

	/* count animation frames */
	for (i = 0; i < count; i++)
	{
		out = &loadmodel->texinfo[i];
		out->numframes = 1;

		for (step = out->next; step && step != out; step = step->next)
		{
			out->numframes++;
		}
	}
}

/*
 * Fills in s->texturemins[] and s->extents[]
 */
static void
Mod_CalcSurfaceExtents(msurface_t *s)
{
	float mins[2], maxs[2], val;
	int i, j, e;
	mvertex_t *v;
	mtexinfo_t *tex;
	int bmins[2], bmaxs[2];

	mins[0] = mins[1] = 999999;
	maxs[0] = maxs[1] = -99999;

	tex = s->texinfo;

	for (i = 0; i < s->numedges; i++)
	{
		e = loadmodel->surfedges[s->firstedge + i];

		if (e >= 0)
		{
			v = &loadmodel->vertexes[loadmodel->edges[e].v[0]];
		}
		else
		{
			v = &loadmodel->vertexes[loadmodel->edges[-e].v[1]];
		}

		for (j = 0; j < 2; j++)
		{
			val = v->position[0] * tex->vecs[j][0] +
				  v->position[1] * tex->vecs[j][1] +
				  v->position[2] * tex->vecs[j][2] +
				  tex->vecs[j][3];

			if (val < mins[j])
			{
				mins[j] = val;
			}

			if (val > maxs[j])
			{
				maxs[j] = val;
			}
		}
	}

	for (i = 0; i < 2; i++)
	{
		bmins[i] = floor(mins[i] / 16);
		bmaxs[i] = ceil(maxs[i] / 16);

		s->texturemins[i] = bmins[i] * 16;
		s->extents[i] = (bmaxs[i] - bmins[i]) * 16;
	}
}

extern void
GL3_SubdivideSurface(msurface_t *fa, gl3model_t* loadmodel);

static void
Mod_LoadFaces(lump_t *l)
{
	dface_t *in;
	msurface_t *out;
	int i, count, surfnum;
	int planenum, side;
	int ti;

	in = (void *)(mod_base + l->fileofs);

	if (l->filelen % sizeof(*in))
	{
		ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: funny lump size in %s",
				loadmodel->name);
	}

	count = l->filelen / sizeof(*in);
	out = Hunk_Alloc(count * sizeof(*out));

	loadmodel->surfaces = out;
	loadmodel->numsurfaces = count;

	currentmodel = loadmodel;

	GL3_LM_BeginBuildingLightmaps(loadmodel);

	for (surfnum = 0; surfnum < count; surfnum++, in++, out++)
	{
		out->firstedge = LittleLong(in->firstedge);
		out->numedges = LittleShort(in->numedges);
		out->flags = 0;
		out->polys = NULL;

		planenum = LittleShort(in->planenum);
		side = LittleShort(in->side);

		if (side)
		{
			out->flags |= SURF_PLANEBACK;
		}

		out->plane = loadmodel->planes + planenum;

		ti = LittleShort(in->texinfo);

		if ((ti < 0) || (ti >= loadmodel->numtexinfo))
		{
			ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: bad texinfo number");
		}

		out->texinfo = loadmodel->texinfo + ti;

		Mod_CalcSurfaceExtents(out);

		/* lighting info */
		for (i = 0; i < MAX_LIGHTMAPS_PER_SURFACE; i++)
		{
			out->styles[i] = in->styles[i];
		}

		i = LittleLong(in->lightofs);

		if (i == -1)
		{
			out->samples = NULL;
		}
		else
		{
			out->samples = loadmodel->lightdata + i;
		}

		/* set the drawing flags */
		if (out->texinfo->flags & SURF_WARP)
		{
			out->flags |= SURF_DRAWTURB;

			for (i = 0; i < 2; i++)
			{
				out->extents[i] = 16384;
				out->texturemins[i] = -8192;
			}

			GL3_SubdivideSurface(out, loadmodel); /* cut up polygon for warps */
		}

		/* create lightmaps and polygons */
		if (!(out->texinfo->flags & (SURF_SKY | SURF_TRANS33 | SURF_TRANS66 | SURF_WARP)))
		{
			GL3_LM_CreateSurfaceLightmap(out);
		}

		if (!(out->texinfo->flags & SURF_WARP))
		{
			GL3_LM_BuildPolygonFromSurface(out);
		}
	}

	GL3_LM_EndBuildingLightmaps();
}

static void
Mod_SetParent(mnode_t *node, mnode_t *parent)
{
	node->parent = parent;

	if (node->contents != -1)
	{
		return;
	}

	Mod_SetParent(node->children[0], node);
	Mod_SetParent(node->children[1], node);
}

static void
Mod_LoadNodes(lump_t *l)
{
	int i, j, count, p;
	dnode_t *in;
	mnode_t *out;

	in = (void *)(mod_base + l->fileofs);

	if (l->filelen % sizeof(*in))
	{
		ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: funny lump size in %s",
				loadmodel->name);
	}

	count = l->filelen / sizeof(*in);
	out = Hunk_Alloc(count * sizeof(*out));

	loadmodel->nodes = out;
	loadmodel->numnodes = count;

	for (i = 0; i < count; i++, in++, out++)
	{
		for (j = 0; j < 3; j++)
		{
			out->minmaxs[j] = LittleShort(in->mins[j]);
			out->minmaxs[3 + j] = LittleShort(in->maxs[j]);
		}

		p = LittleLong(in->planenum);
		out->plane = loadmodel->planes + p;

		out->firstsurface = LittleShort(in->firstface);
		out->numsurfaces = LittleShort(in->numfaces);
		out->contents = -1; /* differentiate from leafs */

		for (j = 0; j < 2; j++)
		{
			p = LittleLong(in->children[j]);

			if (p >= 0)
			{
				out->children[j] = loadmodel->nodes + p;
			}
			else
			{
				out->children[j] = (mnode_t *)(loadmodel->leafs + (-1 - p));
			}
		}
	}

	Mod_SetParent(loadmodel->nodes, NULL); /* sets nodes and leafs */
}

static void
Mod_LoadLeafs(lump_t *l)
{
	dleaf_t *in;
	mleaf_t *out;
	int i, j, count, p;

	in = (void *)(mod_base + l->fileofs);

	if (l->filelen % sizeof(*in))
	{
		ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: funny lump size in %s",
				loadmodel->name);
	}

	count = l->filelen / sizeof(*in);
	out = Hunk_Alloc(count * sizeof(*out));

	loadmodel->leafs = out;
	loadmodel->numleafs = count;

	for (i = 0; i < count; i++, in++, out++)
	{
		unsigned firstleafface;

		for (j = 0; j < 3; j++)
		{
			out->minmaxs[j] = LittleShort(in->mins[j]);
			out->minmaxs[3 + j] = LittleShort(in->maxs[j]);
		}

		p = LittleLong(in->contents);
		out->contents = p;

		out->cluster = LittleShort(in->cluster);
		out->area = LittleShort(in->area);

		// make unsigned long from signed short
		firstleafface = LittleShort(in->firstleafface) & 0xFFFF;
		out->nummarksurfaces = LittleShort(in->numleaffaces) & 0xFFFF;

		out->firstmarksurface = loadmodel->marksurfaces + firstleafface;
		if ((firstleafface + out->nummarksurfaces) > loadmodel->nummarksurfaces)
		{
			ri.Sys_Error (ERR_DROP,"MOD_LoadBmodel: wrong marksurfaces position in %s",loadmodel->name);
		}
	}
}

static void
Mod_LoadMarksurfaces(lump_t *l)
{
	int i, j, count;
	short *in;
	msurface_t **out;

	in = (void *)(mod_base + l->fileofs);

	if (l->filelen % sizeof(*in))
	{
		ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: funny lump size in %s",
				loadmodel->name);
	}

	count = l->filelen / sizeof(*in);
	out = Hunk_Alloc(count * sizeof(*out));

	loadmodel->marksurfaces = out;
	loadmodel->nummarksurfaces = count;

	for (i = 0; i < count; i++)
	{
		j = LittleShort(in[i]);

		if ((j < 0) || (j >= loadmodel->numsurfaces))
		{
			ri.Sys_Error(ERR_DROP, "Mod_ParseMarksurfaces: bad surface number");
		}

		out[i] = loadmodel->surfaces + j;
	}
}

static void
Mod_LoadSurfedges(lump_t *l)
{
	int i, count;
	int *in, *out;

	in = (void *)(mod_base + l->fileofs);

	if (l->filelen % sizeof(*in))
	{
		ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: funny lump size in %s",
				loadmodel->name);
	}

	count = l->filelen / sizeof(*in);

	if ((count < 1) || (count >= MAX_MAP_SURFEDGES))
	{
		ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: bad surfedges count in %s: %i",
				loadmodel->name, count);
	}

	out = Hunk_Alloc(count * sizeof(*out));

	loadmodel->surfedges = out;
	loadmodel->numsurfedges = count;

	for (i = 0; i < count; i++)
	{
		out[i] = LittleLong(in[i]);
	}
}

static void
Mod_LoadPlanes(lump_t *l)
{
	int i, j;
	cplane_t *out;
	dplane_t *in;
	int count;
	int bits;

	in = (void *)(mod_base + l->fileofs);

	if (l->filelen % sizeof(*in))
	{
		ri.Sys_Error(ERR_DROP, "MOD_LoadBmodel: funny lump size in %s",
				loadmodel->name);
	}

	count = l->filelen / sizeof(*in);
	out = Hunk_Alloc(count * 2 * sizeof(*out));

	loadmodel->planes = out;
	loadmodel->numplanes = count;

	for (i = 0; i < count; i++, in++, out++)
	{
		bits = 0;

		for (j = 0; j < 3; j++)
		{
			out->normal[j] = LittleFloat(in->normal[j]);

			if (out->normal[j] < 0)
			{
				bits |= 1 << j;
			}
		}

		out->dist = LittleFloat(in->dist);
		out->type = LittleLong(in->type);
		out->signbits = bits;
	}
}

static void
Mod_LoadBrushModel(gl3model_t *mod, void *buffer, int modfilelen)
{
	int i;
	dheader_t *header;
	mmodel_t *bm;

	/* Because Quake II is is sometimes so ... "optimized" this
	 * is going to be somewhat dirty. The map data contains indices
	 * that we're converting into pointers. Yeah. No comments. The
	 * indices are 32 bit long, they just encode the offset between
	 * the hunks base address and the position in the hunk, so 32 bit
	 * pointers should be enough. But let's play save, waste some
	 * allocations and just take the plattforms pointer size instead
	 * of relying on assumptions. */
	loadmodel->extradata = Hunk_Begin(modfilelen * sizeof(void*));
	loadmodel->type = mod_brush;

	if (loadmodel != mod_known)
	{
		ri.Sys_Error(ERR_DROP, "Loaded a brush model after the world");
	}

	header = (dheader_t *)buffer;

	i = LittleLong(header->version);

	if (i != BSPVERSION)
	{
		ri.Sys_Error(ERR_DROP, "Mod_LoadBrushModel: %s has wrong version number (%i should be %i)",
				mod->name, i, BSPVERSION);
	}

	/* swap all the lumps */
	mod_base = (byte *)header;

	for (i = 0; i < sizeof(dheader_t) / 4; i++)
	{
		((int *)header)[i] = LittleLong(((int *)header)[i]);
	}

	/* load into heap */
	Mod_LoadVertexes(&header->lumps[LUMP_VERTEXES]);
	Mod_LoadEdges(&header->lumps[LUMP_EDGES]);
	Mod_LoadSurfedges(&header->lumps[LUMP_SURFEDGES]);
	Mod_LoadLighting(&header->lumps[LUMP_LIGHTING]);
	Mod_LoadPlanes(&header->lumps[LUMP_PLANES]);
	Mod_LoadTexinfo(&header->lumps[LUMP_TEXINFO]);
	Mod_LoadFaces(&header->lumps[LUMP_FACES]);
	Mod_LoadMarksurfaces(&header->lumps[LUMP_LEAFFACES]);
	Mod_LoadVisibility(&header->lumps[LUMP_VISIBILITY]);
	Mod_LoadLeafs(&header->lumps[LUMP_LEAFS]);
	Mod_LoadNodes(&header->lumps[LUMP_NODES]);
	Mod_LoadSubmodels(&header->lumps[LUMP_MODELS]);
	mod->numframes = 2; /* regular and alternate animation */

	/* set up the submodels */
	for (i = 0; i < mod->numsubmodels; i++)
	{
		gl3model_t *starmod;

		bm = &mod->submodels[i];
		starmod = &mod_inline[i];

		*starmod = *loadmodel;

		starmod->firstmodelsurface = bm->firstface;
		starmod->nummodelsurfaces = bm->numfaces;
		starmod->firstnode = bm->headnode;

		if (starmod->firstnode >= loadmodel->numnodes)
		{
			ri.Sys_Error(ERR_DROP, "Inline model %i has bad firstnode", i);
		}

		VectorCopy(bm->maxs, starmod->maxs);
		VectorCopy(bm->mins, starmod->mins);
		starmod->radius = bm->radius;

		if (i == 0)
		{
			*loadmodel = *starmod;
		}

		starmod->numleafs = bm->visleafs;
	}
}

static void
Mod_Free(gl3model_t *mod)
{
	Hunk_Free(mod->extradata);
	memset(mod, 0, sizeof(*mod));
}

void
GL3_Mod_FreeAll(void)
{
	int i;

	for (i = 0; i < mod_numknown; i++)
	{
		if (mod_known[i].extradatasize)
		{
			Mod_Free(&mod_known[i]);
		}
	}
}

extern void GL3_LoadMD2(gl3model_t *mod, void *buffer, int modfilelen);
extern void GL3_LoadSP2(gl3model_t *mod, void *buffer, int modfilelen);

/*
=================
GL3_LoadMD3
Basic MD3 to MD2 converter - loads only first surface
=================
*/
static void
GL3_LoadMD3(gl3model_t *mod, void *buffer, int modfilelen)
{
    int i, j;
    dmd3header_t *pinmodel;
    dmd3surface_t *pinsurface;
    dmd3frame_t *pinframe;
    int version;
    dmdl_t *poutmodel;
    int total_size;
    
    pinmodel = (dmd3header_t *)buffer;
    version = LittleLong(pinmodel->version);
    
    if (version != MD3_VERSION)
    {
        ri.Sys_Error(ERR_DROP, "%s has wrong version number (%i should be %i)",
                     mod->name, version, MD3_VERSION);
    }
    
    // MD3 models can have multiple surfaces, we only load the first
    int numSurfaces = LittleLong(pinmodel->numSurfaces);
    if (numSurfaces <= 0)
    {
        ri.Sys_Error(ERR_DROP, "%s has no surfaces", mod->name);
    }
    
    // Get first surface
    pinsurface = (dmd3surface_t *)((byte *)buffer + LittleLong(pinmodel->ofsSurfaces));

    // Convert to MD2 format
    int numFrames = LittleLong(pinsurface->numFrames);
    int numVerts = LittleLong(pinsurface->numVerts);
    int numTris = LittleLong(pinsurface->numTriangles);
    
    // First, calculate framesize
    int framesize = sizeof(daliasframe_t) + numVerts * sizeof(dtrivertx_t);

    // We need to allocate enough space for the converted MD2 data
    // AND ensure we can read all the MD3 data
    int md3_size = LittleLong(pinsurface->ofsEnd);  // Size of the MD3 surface
    int md2_size = sizeof(dmdl_t) +                  // header
                   1 * MAX_SKINNAME +                 // 1 skin name
                   numVerts * sizeof(dstvert_t) +     // ST coords
                   numTris * sizeof(dtriangle_t) +    // triangles
                   numFrames * framesize +            // frames with vertices
                   0;                                 // no GL commands

    total_size = md2_size;  // We only need to allocate space for MD2

    mod->extradata = Hunk_Begin(total_size);
    if (!mod->extradata) {
        ri.Sys_Error(ERR_DROP, "GL3_LoadMD3: out of hunk memory (need %d bytes)", total_size);
    }

    poutmodel = Hunk_Alloc(total_size);
    if (!poutmodel) {
        ri.Sys_Error(ERR_DROP, "GL3_LoadMD3: failed to allocate %d bytes", total_size);
    }
    memset(poutmodel, 0, total_size);

    // NOW fill in the MD2 header
    poutmodel->ident = IDALIASHEADER;
    poutmodel->version = ALIAS_VERSION;
    poutmodel->skinwidth = 256;
    poutmodel->skinheight = 256;
    poutmodel->framesize = framesize;
    poutmodel->num_skins = 1;
    poutmodel->num_xyz = numVerts;
    poutmodel->num_st = numVerts;
    poutmodel->num_tris = numTris;
    poutmodel->num_glcmds = 0;
    poutmodel->num_frames = numFrames;

    // Set up offsets
    poutmodel->ofs_skins = sizeof(dmdl_t);
    poutmodel->ofs_st = poutmodel->ofs_skins + poutmodel->num_skins * MAX_SKINNAME;
    poutmodel->ofs_tris = poutmodel->ofs_st + poutmodel->num_st * sizeof(dstvert_t);
    poutmodel->ofs_frames = poutmodel->ofs_tris + poutmodel->num_tris * sizeof(dtriangle_t);
    poutmodel->ofs_glcmds = poutmodel->ofs_frames + poutmodel->num_frames * poutmodel->framesize;
    poutmodel->ofs_end = poutmodel->ofs_glcmds;

    // ADD THE SANITY CHECK HERE:
    if (poutmodel->ofs_end > total_size) {
        ri.Sys_Error(ERR_DROP, "GL3_LoadMD3: calculated offsets exceed allocated size!");
    }

    // Verify frame size
    int actual_framesize = poutmodel->ofs_glcmds - poutmodel->ofs_frames;

    // Copy skin name to the correct location
    char *skinname = (char *)poutmodel + poutmodel->ofs_skins;
    strcpy(skinname, "models/default.pcx");

    // Set up dummy ST coordinates at the correct offset
    dstvert_t *poutst = (dstvert_t *)((byte *)poutmodel + poutmodel->ofs_st);
    float *pinst = (float *)((byte *)pinsurface + LittleLong(pinsurface->ofsST));

    for (i = 0; i < numVerts; i++)
    {
        poutst[i].s = (short)(LittleFloat(pinst[i * 2 + 0]) * poutmodel->skinwidth);
        poutst[i].t = (short)(LittleFloat(pinst[i * 2 + 1]) * poutmodel->skinheight);
    }
    
    // Load frames from MD3
    // Load frames from MD3
    int vertexOffset = LittleLong(pinsurface->ofsVertexes);

    for (i = 0; i < numFrames; i++)
    {
        daliasframe_t *poutframe = (daliasframe_t *)((byte *)poutmodel +
                                   poutmodel->ofs_frames + i * poutmodel->framesize);
        
        // Get MD3 frame info
        pinframe = (dmd3frame_t *)((byte *)buffer + LittleLong(pinmodel->ofsFrames) +
                                   i * sizeof(dmd3frame_t));
        
        strcpy(poutframe->name, pinframe->name);
        
        // Calculate scale and translate
        for (j = 0; j < 3; j++)
        {
            float min = LittleFloat(pinframe->mins[j]);
            float max = LittleFloat(pinframe->maxs[j]);
            
            // Ensure we have valid bounds
            if (max <= min) {
                max = min + 1.0f;
            }
            
            poutframe->scale[j] = (max - min) / 255.0f;
            if (poutframe->scale[j] <= 0) {
                poutframe->scale[j] = 1.0f / 255.0f;
            }
            poutframe->translate[j] = min;
        }
        
        // Convert vertices
        dtrivertx_t *poutvert = poutframe->verts;

        // MD3 vertices are stored as shorts, not floats!
        // Each vertex is 8 bytes (4 shorts: x,y,z,normal)
        short *pinverts = (short *)((byte *)pinsurface + vertexOffset);

        for (j = 0; j < numVerts; j++)
        {
            // Get vertex for this frame
            // MD3 stores all vertices for frame 0, then all for frame 1, etc.
            short *vert = &pinverts[(i * numVerts + j) * 4];
            
            // MD3 stores vertices as shorts with scale factor of 1.0/64
            vec3_t v;
            v[0] = (float)(LittleShort(vert[0])) * (1.0f/64.0f);
            v[1] = (float)(LittleShort(vert[1])) * (1.0f/64.0f);
            v[2] = (float)(LittleShort(vert[2])) * (1.0f/64.0f);
            
            // Scale to byte range
            poutvert[j].v[0] = (byte)((v[0] - poutframe->translate[0]) / poutframe->scale[0]);
            poutvert[j].v[1] = (byte)((v[1] - poutframe->translate[1]) / poutframe->scale[1]);
            poutvert[j].v[2] = (byte)((v[2] - poutframe->translate[2]) / poutframe->scale[2]);
            poutvert[j].lightnormalindex = 0;
        }
    }
    
    // Set model type
    mod->type = mod_alias;

    // Set model bounds (important for culling)
    mod->mins[0] = LittleFloat(pinframe->mins[0]);
    mod->mins[1] = LittleFloat(pinframe->mins[1]);
    mod->mins[2] = LittleFloat(pinframe->mins[2]);
    mod->maxs[0] = LittleFloat(pinframe->maxs[0]);
    mod->maxs[1] = LittleFloat(pinframe->maxs[1]);
    mod->maxs[2] = LittleFloat(pinframe->maxs[2]);

    // Calculate radius for culling
    float dx = mod->maxs[0] - mod->mins[0];
    float dy = mod->maxs[1] - mod->mins[1];
    float dz = mod->maxs[2] - mod->mins[2];
    mod->radius = sqrt(dx*dx + dy*dy + dz*dz) * 0.5f;
    
    // Initialize skins to NULL
    for (i = 0; i < MAX_MD2SKINS; i++) {
        mod->skins[i] = NULL;
    }

    // Try to load shader names from MD3
    int numShaders = LittleLong(pinsurface->numShaders);
    if (numShaders > 0 && numShaders < MAX_MD2SKINS) {
        int ofsShaders = LittleLong(pinsurface->ofsShaders);
        if (ofsShaders > 0 && ofsShaders < modfilelen) {
            char *shadername = (char *)((byte *)pinsurface + ofsShaders);
            // MD3 shaders are 64-byte entries
            for (i = 0; i < numShaders && i < MAX_MD2SKINS; i++) {
                char shader_path[MAX_QPATH];
                strncpy(shader_path, shadername + (i * 64), 63);
                shader_path[63] = '\0';
                
                // Skip empty shader names
                if (shader_path[0] != '\0') {
                    // Try to load the shader/texture
                    mod->skins[i] = GL3_FindImage(shader_path, it_skin);
                    if (!mod->skins[i]) {
                        // If failed, try with common extensions
                        char tex_path[MAX_QPATH];
                        Com_sprintf(tex_path, sizeof(tex_path), "%s.tga", shader_path);
                        mod->skins[i] = GL3_FindImage(tex_path, it_skin);
                    }
                }
            }
        }
    }

    // If no skins loaded, use a default
    if (!mod->skins[0]) {
        mod->skins[0] = GL3_FindImage("pics/colormap.pcx", it_skin);
    }

    // Make sure extradata points to the model header
    mod->extradata = poutmodel;
}

/*
 * Loads in a model for the given name
 */
static gl3model_t *
Mod_ForName(char *name, qboolean crash)
{
	gl3model_t *mod;
	unsigned *buf;
	int i;

	if (!name[0])
	{
		ri.Sys_Error(ERR_DROP, "Mod_ForName: NULL name");
	}

	/* inline models are grabbed only from worldmodel */
	if (name[0] == '*')
	{
		i = (int)strtol(name + 1, (char **)NULL, 10);

		if ((i < 1) || !gl3_worldmodel || (i >= gl3_worldmodel->numsubmodels))
		{
			ri.Sys_Error(ERR_DROP, "bad inline model number");
		}

		return &mod_inline[i];
	}

	/* search the currently loaded models */
	for (i = 0, mod = mod_known; i < mod_numknown; i++, mod++)
	{
		if (!mod->name[0])
		{
			continue;
		}

		if (!strcmp(mod->name, name))
		{
			return mod;
		}
	}

	/* find a free model slot spot */
	for (i = 0, mod = mod_known; i < mod_numknown; i++, mod++)
	{
		if (!mod->name[0])
		{
			break; /* free spot */
		}
	}

	if (i == mod_numknown)
	{
		if (mod_numknown == MAX_MOD_KNOWN)
		{
			ri.Sys_Error(ERR_DROP, "mod_numknown == MAX_MOD_KNOWN");
		}

		mod_numknown++;
	}

	strcpy(mod->name, name);

	/* load the file */
	int modfilelen = ri.FS_LoadFile(mod->name, (void **)&buf);

	if (!buf)
	{
		if (crash)
		{
			ri.Sys_Error(ERR_DROP, "Mod_NumForName: %s not found", mod->name);
		}

		memset(mod->name, 0, sizeof(mod->name));
		return NULL;
	}

	loadmodel = mod;

	/* call the apropriate loader */
	switch (LittleLong(*(unsigned *)buf))
	{
		case IDALIASHEADER:
			GL3_LoadMD2(mod, buf, modfilelen);
			break;
            
        case IDMD3HEADER:
            GL3_LoadMD3(mod, buf, modfilelen);  // Note: GL3_LoadMD3, not Mod_LoadMD3Model
            break;

		case IDSPRITEHEADER:
			GL3_LoadSP2(mod, buf, modfilelen);
			break;

		case IDBSPHEADER:
			Mod_LoadBrushModel(mod, buf, modfilelen);
			break;

		default:
			ri.Sys_Error(ERR_DROP,
				"Mod_NumForName: unknown fileid for %s",
				mod->name);
			break;
	}

	loadmodel->extradatasize = Hunk_End();

	ri.FS_FreeFile(buf);

	return mod;
}

/*
 * Specifies the model that will be used as the world
 */
void
GL3_BeginRegistration(char *model)
{
	char fullname[MAX_QPATH];
	cvar_t *flushmap;

	registration_sequence++;
	gl3_oldviewcluster = -1; /* force markleafs */

	gl3state.currentlightmap = -1;

	Com_sprintf(fullname, sizeof(fullname), "maps/%s.bsp", model);

	/* explicitly free the old map if different
	   this guarantees that mod_known[0] is the
	   world map */
	flushmap = ri.Cvar_Get("flushmap", "0", 0);

	if (strcmp(mod_known[0].name, fullname) || flushmap->value)
	{
		Mod_Free(&mod_known[0]);
	}

	gl3_worldmodel = Mod_ForName(fullname, true);

	gl3_viewcluster = -1;
}

struct model_s *
GL3_RegisterModel(char *name)
{
	gl3model_t *mod;
	int i;
	dsprite_t *sprout;
	dmdl_t *pheader;

	mod = Mod_ForName(name, false);

	if (mod)
	{
		mod->registration_sequence = registration_sequence;

		/* register any images used by the models */
		if (mod->type == mod_sprite)
		{
			sprout = (dsprite_t *)mod->extradata;

			for (i = 0; i < sprout->numframes; i++)
			{
				mod->skins[i] = GL3_FindImage(sprout->frames[i].name, it_sprite);
			}
		}
		else if (mod->type == mod_alias)
		{
			pheader = (dmdl_t *)mod->extradata;

			for (i = 0; i < pheader->num_skins; i++)
			{
				mod->skins[i] = GL3_FindImage((char *)pheader + pheader->ofs_skins + i * MAX_SKINNAME, it_skin);
			}

			mod->numframes = pheader->num_frames;
		}
		else if (mod->type == mod_brush)
		{
			for (i = 0; i < mod->numtexinfo; i++)
			{
				mod->texinfo[i].image->registration_sequence = registration_sequence;
			}
		}
	}

	return mod;
}

void
GL3_EndRegistration(void)
{
	int i;
	gl3model_t *mod;

	for (i = 0, mod = mod_known; i < mod_numknown; i++, mod++)
	{
		if (!mod->name[0])
		{
			continue;
		}

		if (mod->registration_sequence != registration_sequence)
		{
			/* don't need this model */
			Mod_Free(mod);
		}
	}

	GL3_FreeUnusedImages();
}
