package display;

class LevelRender extends dn.Process {
	static var FIELD_TEXT_SCALE = 0.666;

	public var editor(get,never) : Editor; inline function get_editor() return Editor.ME;
	public var camera(get,never) : display.Camera; inline function get_camera() return Editor.ME.camera;
	public var settings(get,never) : AppSettings; inline function get_settings() return App.ME.settings;

	/** <LayerDefUID, Bool> **/
	var autoLayerRendering : Map<Int,Bool> = new Map();

	/** <LayerDefUID, Bool> **/
	var layerVis : Map<Int,Bool> = new Map();

	var layersWrapper : h2d.Layers;

	/** <LayerDefUID, h2d.Object> **/
	var layerRenders : Map<Int,h2d.Object> = new Map();

	var bg : h2d.Bitmap;
	var bounds : h2d.Graphics;
	var boundsGlow : h2d.Graphics;
	var grid : h2d.Graphics;
	var rectBleeps : Array<h2d.Object> = [];
	public var temp : h2d.Graphics;

	// Invalidation system (ie. render calls)
	var allInvalidated = true;
	var uiInvalidated = false;
	var layerInvalidations : Map<Int, { left:Int, right:Int, top:Int, bottom:Int }> = new Map();


	public function new() {
		super(editor);

		editor.ge.addGlobalListener(onGlobalEvent);
		createRootInLayers(editor.root, Const.DP_MAIN);

		bg = new h2d.Bitmap();
		root.add(bg, Const.DP_BG);

		bounds = new h2d.Graphics();
		root.add(bounds, Const.DP_UI);

		boundsGlow = new h2d.Graphics();
		root.add(boundsGlow, Const.DP_UI);

		grid = new h2d.Graphics();
		root.add(grid, Const.DP_UI);

		layersWrapper = new h2d.Layers();
		root.add(layersWrapper, Const.DP_MAIN);

		temp = new h2d.Graphics();
		root.add(temp, Const.DP_TOP);
	}

	override function onDispose() {
		super.onDispose();
		editor.ge.removeListener(onGlobalEvent);
	}

	function onGlobalEvent(e:GlobalEvent) {
		switch e {
			case WorldMode(active):
				if( active ) {
					// Remove hidden render
					for(l in layerRenders)
						l.remove();
					layerRenders = new Map();
					grid.clear();

					// Stop process
					pause();
					root.visible = false;
				}
				else {
					// Resume
					root.visible = true;
					invalidateAll();
					resume();
				}

			case GridChanged(active):
				applyGridVisibility();

			case ViewportChanged, WorldLevelMoved, WorldSettingsChanged:
				root.setScale( camera.adjustedZoom );
				root.x = M.round( editor.camera.width*0.5 - camera.levelX * camera.adjustedZoom );
				root.y = M.round( editor.camera.height*0.5 - camera.levelY * camera.adjustedZoom );

			case ProjectSaved, BeforeProjectSaving:

			case ProjectSelected:
				renderAll();

			case ProjectSettingsChanged:
				invalidateUi();

			case LevelRestoredFromHistory(l):
				invalidateAll();

			case LayerInstanceRestoredFromHistory(li):
				invalidateLayer(li);

			case LevelSelected(l):
				invalidateAll();

			case LevelResized(l):
				for(li in l.layerInstances)
					if( li.def.isAutoLayer() )
						li.applyAllAutoLayerRules();
				invalidateAll();

			case LayerInstanceVisiblityChanged(li):
				applyLayerVisibility(li);

			case LayerInstanceAutoRenderingChanged(li):
				invalidateLayer(li);

			case LayerInstanceSelected:
				applyAllLayersVisibility();
				invalidateUi();

			case LevelSettingsChanged(l):
				invalidateUi();

			case LayerDefRemoved(uid):
				if( layerRenders.exists(uid) ) {
					layerRenders.get(uid).remove();
					layerRenders.remove(uid);
					for(li in editor.curLevel.layerInstances)
						if( !li.def.autoLayerRulesCanBeUsed() )
							invalidateLayer(li);
				}

			case LayerDefSorted:
				for( li in editor.curLevel.layerInstances ) {
					var depth = editor.project.defs.getLayerDepth(li.def);
					if( layerRenders.exists(li.layerDefUid) )
						layersWrapper.add( layerRenders.get(li.layerDefUid), depth );
				}

			case LayerDefChanged, LayerDefConverted:
				invalidateAll();

			case LayerRuleChanged(r), LayerRuleAdded(r):
				var li = editor.curLevel.getLayerInstanceFromRule(r);
				li.applyAutoLayerRuleToAllLayer(r, true);
				invalidateLayer(li);

			case LayerRuleSeedChanged:
				invalidateLayer( editor.curLayerInstance );

			case LayerRuleSorted:
				invalidateLayer( editor.curLayerInstance );

			case LayerRuleRemoved(r):
				var li = editor.curLevel.getLayerInstanceFromRule(r);
				invalidateLayer( li==null ? editor.curLayerInstance : li );

			case LayerRuleGroupAdded:

			case LayerRuleGroupRemoved(rg):
				editor.curLayerInstance.applyAllAutoLayerRules();
				invalidateLayer( editor.curLayerInstance );

			case LayerRuleGroupChanged(rg):
				invalidateLayer( editor.curLayerInstance );

			case LayerRuleGroupChangedActiveState(rg):
				invalidateLayer( editor.curLayerInstance );

			case LayerRuleGroupSorted:
				invalidateLayer( editor.curLayerInstance );

			case LayerRuleGroupCollapseChanged:

			case LayerInstanceChanged:

			case TilesetSelectionSaved(td):

			case TilesetDefPixelDataCacheRebuilt(td):

			case TilesetDefRemoved(td):
				invalidateAll();

			case TilesetDefChanged(td):
				for(li in editor.curLevel.layerInstances)
					if( li.def.isUsingTileset(td) )
						invalidateLayer(li);

			case TilesetDefAdded(td):

			case EntityDefRemoved, EntityDefChanged, EntityDefSorted:
				for(li in editor.curLevel.layerInstances)
					if( li.def.type==Entities )
						invalidateLayer(li);

			case EntityFieldAdded(ed), EntityFieldRemoved(ed), EntityFieldDefChanged(ed):
				if( editor.curLayerInstance!=null ) {
					var li = editor.curLevel.getLayerInstanceFromEntity(ed);
					invalidateLayer( li==null ? editor.curLayerInstance : li );
				}

			case EnumDefRemoved, EnumDefChanged, EnumDefValueRemoved:
				for(li in editor.curLevel.layerInstances)
					if( li.def.type==Entities )
						invalidateLayer(li);

			case EntityInstanceAdded(ei), EntityInstanceRemoved(ei), EntityInstanceChanged(ei), EntityInstanceFieldChanged(ei):
				var li = editor.curLevel.getLayerInstanceFromEntity(ei);
				invalidateLayer( li==null ? editor.curLayerInstance : li );

			case LevelAdded(l):

			case LevelRemoved(l):

			case LevelSorted:
			case LayerDefAdded:

			case EntityDefAdded:
			case EntityFieldSorted:

			case ToolOptionChanged:

			case EnumDefAdded:
			case EnumDefSorted:
		}
	}

	public inline function autoLayerRenderingEnabled(li:data.inst.LayerInstance) {
		if( li==null || !li.def.isAutoLayer() )
			return false;

		return ( !autoLayerRendering.exists(li.layerDefUid) || autoLayerRendering.get(li.layerDefUid)==true );
	}

	public function setAutoLayerRendering(li:data.inst.LayerInstance, v:Bool) {
		if( li==null || !li.def.isAutoLayer() )
			return;

		autoLayerRendering.set(li.layerDefUid, v);
		editor.ge.emit( LayerInstanceAutoRenderingChanged(li) );
	}

	public function toggleAutoLayerRendering(li:data.inst.LayerInstance) {
		if( li!=null && li.def.isAutoLayer() )
			setAutoLayerRendering( li, !autoLayerRenderingEnabled(li) );
	}

	public inline function isLayerVisible(l:data.inst.LayerInstance) {
		return l!=null && ( !layerVis.exists(l.layerDefUid) || layerVis.get(l.layerDefUid)==true );
	}

	public function toggleLayer(li:data.inst.LayerInstance) {
		layerVis.set(li.layerDefUid, !isLayerVisible(li));
		editor.ge.emit( LayerInstanceVisiblityChanged(li) );

		if( isLayerVisible(li) )
			invalidateLayer(li);
	}

	public function showLayer(li:data.inst.LayerInstance) {
		layerVis.set(li.layerDefUid, true);
		editor.ge.emit( LayerInstanceVisiblityChanged(li) );
	}

	public function hideLayer(li:data.inst.LayerInstance) {
		layerVis.set(li.layerDefUid, false);
		editor.ge.emit( LayerInstanceVisiblityChanged(li) );
	}

	public function bleepRectPx(x:Int, y:Int, w:Int, h:Int, col:UInt, thickness=1) {
		var pad = 5;
		var g = new h2d.Graphics();
		rectBleeps.push(g);
		g.lineStyle(thickness, col);
		g.drawRect( Std.int(-pad-w*0.5), Std.int(-pad-h*0.5), w+pad*2, h+pad*2 );
		g.setPosition(
			Std.int(x+w*0.5) + editor.curLayerInstance.pxTotalOffsetX,
			Std.int(y+h*0.5) + editor.curLayerInstance.pxTotalOffsetY
		);
		root.add(g, Const.DP_UI);
	}

	public inline function bleepRectCase(cx:Int, cy:Int, cWid:Int, cHei:Int, col:UInt, thickness=1) {
		var li = editor.curLayerInstance;
		bleepRectPx(
			cx*li.def.gridSize,
			cy*li.def.gridSize,
			cWid*li.def.gridSize,
			cHei*li.def.gridSize,
			col, 2
		);
	}

	public inline function bleepHistoryBounds(layerId:Int, bounds:HistoryStateBounds, col:UInt) {
		bleepRectPx(bounds.x, bounds.y, bounds.wid, bounds.hei, col, 2);
	}
	public inline function bleepEntity(ei:data.inst.EntityInstance) {
		bleepRectPx(
			Std.int( ei.x-ei.def.width*ei.def.pivotX ),
			Std.int( ei.y-ei.def.height*ei.def.pivotY ),
			ei.def.width,
			ei.def.height,
			ei.getSmartColor(true), 2
		);
	}

	public inline function bleepPoint(x:Float, y:Float, col:UInt, thickness=2) {
		var g = new h2d.Graphics();
		rectBleeps.push(g);
		g.lineStyle(thickness, col);
		g.drawCircle( 0,0, 16 );
		g.setPosition( M.round(x), M.round(y) );
		root.add(g, Const.DP_UI);
	}


	function renderBg() {
		var c = editor.curLevel.getBgColor();
		bg.tile = h2d.Tile.fromColor(c);
		bg.scaleX = editor.curLevel.pxWid;
		bg.scaleY = editor.curLevel.pxHei;
	}

	function renderBounds() {
		// Bounds
		bounds.clear();
		bounds.lineStyle(1, 0xffffff, 0.7);
		bounds.drawRect(0, 0, editor.curLevel.pxWid, editor.curLevel.pxHei);

		// Bounds glow/shadow
		boundsGlow.clear();
		boundsGlow.beginFill(0xff00ff);
		boundsGlow.drawRect(0, 0, editor.curLevel.pxWid, editor.curLevel.pxHei);
		var shadow = new h2d.filter.Glow( 0x0, 0.6, 128, true );
		shadow.knockout = true;
		boundsGlow.filter = shadow;
	}

	inline function applyGridVisibility() {
		grid.visible = settings.grid && !editor.worldMode;
	}

	function renderGrid() {
		grid.clear();
		applyGridVisibility();

		if( editor.curLayerInstance==null )
			return;

		var col = C.getPerceivedLuminosityInt( editor.project.bgColor) >= 0.8 ? 0x0 : 0xffffff;

		var li = editor.curLayerInstance;
		var level = editor.curLevel;
		grid.lineStyle(1, col, 0.07);

		// Verticals
		var x = 0;
		for( cx in 0...editor.curLayerInstance.cWid+1 ) {
			x = cx*li.def.gridSize + li.pxTotalOffsetX;
			if( x<0 || x>=level.pxWid )
				continue;

			grid.moveTo( x, M.fmax(0,li.pxTotalOffsetY) );
			grid.lineTo( x, M.fmin(li.cHei*li.def.gridSize, level.pxHei) );
		}
		// Horizontals
		var y = 0;
		for( cy in 0...editor.curLayerInstance.cHei+1 ) {
			y = cy*li.def.gridSize + li.pxTotalOffsetY;
			if( y<0 || y>=level.pxHei)
				continue;

			grid.moveTo( M.fmax(0,li.pxTotalOffsetX), y );
			grid.lineTo( M.fmin(li.cWid*li.def.gridSize, level.pxWid), y );
		}
	}


	public function renderAll() {
		allInvalidated = false;

		clearTemp();
		renderBounds();
		renderGrid();
		renderBg();

		for(ld in editor.project.defs.layers)
			renderLayer( editor.curLevel.getLayerInstance(ld) );
	}

	public inline function clearTemp() {
		temp.clear();
	}


	function renderLayer(li:data.inst.LayerInstance) {
		layerInvalidations.remove(li.layerDefUid);

		// Create wrapper
		if( layerRenders.exists(li.layerDefUid) )
			layerRenders.get(li.layerDefUid).remove();

		var wrapper = new h2d.Object();
		wrapper.x = li.pxTotalOffsetX;
		wrapper.y = li.pxTotalOffsetY;

		// Register it
		layerRenders.set(li.layerDefUid, wrapper);
		var depth = editor.project.defs.getLayerDepth(li.def);
		layersWrapper.add( wrapper, depth );

		// Render
		switch li.def.type {
		case IntGrid, AutoLayer:
			// var doneCoords = new Map();

			if( li.def.isAutoLayer() && li.def.autoTilesetDefUid!=null && autoLayerRenderingEnabled(li) ) {
				// Auto-layer tiles
				var td = editor.project.defs.getTilesetDef( li.def.autoTilesetDefUid );
				var tg = new h2d.TileGroup( td.getAtlasTile(), wrapper);

				if( li.autoTilesCache==null )
					li.applyAllAutoLayerRules();

				li.def.iterateActiveRulesInDisplayOrder( (r)-> {
					if( li.autoTilesCache.exists( r.uid ) ) {
						for(coordId in li.autoTilesCache.get( r.uid ).keys()) {
							// doneCoords.set(coordId, true);
							for(tileInfos in li.autoTilesCache.get( r.uid ).get(coordId)) {
								tg.addTransform(
									tileInfos.x + ( ( dn.M.hasBit(tileInfos.flips,0)?1:0 ) + li.def.tilePivotX ) * li.def.gridSize,
									tileInfos.y + ( ( dn.M.hasBit(tileInfos.flips,1)?1:0 ) + li.def.tilePivotY ) * li.def.gridSize,
									dn.M.hasBit(tileInfos.flips,0)?-1:1,
									dn.M.hasBit(tileInfos.flips,1)?-1:1,
									0,
									td.extractTile(tileInfos.srcX, tileInfos.srcY)
								);
							}
						}
					}
				});

				// Default render when no rule match here
				// if( li.def.type==IntGrid )
				// 	for(cy in 0...li.cHei)
				// 	for(cx in 0...li.cWid) {
				// 		if( doneCoords.exists(li.coordId(cx,cy)) || li.getIntGrid(cx,cy)<0 )
				// 			continue;
				// 		g.lineStyle(1, li.getIntGridColorAt(cx,cy), 0.6 );
				// 		g.drawRect(cx*li.def.gridSize+2, cy*li.def.gridSize+2, li.def.gridSize-4, li.def.gridSize-4);
				// 	}
			}
			else if( li.def.type==IntGrid ) {
				// Normal intGrid
				var pixelGrid = new dn.heaps.PixelGrid(li.def.gridSize, li.cWid, li.cHei, wrapper);

				for(cy in 0...li.cHei)
				for(cx in 0...li.cWid)
					if( li.hasIntGrid(cx,cy) )
						pixelGrid.setPixel( cx, cy, li.getIntGridColorAt(cx,cy) );
			}

		case Entities:
			for(ei in li.entityInstances) {
				var e = createEntityRender(ei, li);
				e.setPosition(ei.x, ei.y);
				wrapper.addChild(e);
			}

		case Tiles:
			var td = editor.project.defs.getTilesetDef(li.def.tilesetDefUid);
			if( td!=null && td.isAtlasLoaded() ) {
				var tg = new h2d.TileGroup( td.getAtlasTile(), wrapper );

				for(cy in 0...li.cHei)
				for(cx in 0...li.cWid) {
					if( !li.hasAnyGridTile(cx,cy) )
						continue;

					for( tileInf in li.getGridTileStack(cx,cy) ) {
						var t = td.getTile(tileInf.tileId);
						t.setCenterRatio(li.def.tilePivotX, li.def.tilePivotY);
						var sx = M.hasBit(tileInf.flips, 0) ? -1 : 1;
						var sy = M.hasBit(tileInf.flips, 1) ? -1 : 1;
						tg.addTransform(
							(cx + li.def.tilePivotX + (sx<0?1:0)) * li.def.gridSize,
							(cy + li.def.tilePivotX + (sy<0?1:0)) * li.def.gridSize,
							sx,
							sy,
							0,
							t
						);
					}
				}
			}
			else {
				// Missing tileset
				var tileError = data.def.TilesetDef.makeErrorTile(li.def.gridSize);
				var tg = new h2d.TileGroup( tileError, wrapper );
				for(cy in 0...li.cHei)
				for(cx in 0...li.cWid)
					if( li.hasAnyGridTile(cx,cy) )
						tg.add(
							(cx + li.def.tilePivotX) * li.def.gridSize,
							(cy + li.def.tilePivotX) * li.def.gridSize,
							tileError
						);
			}
		}

		applyLayerVisibility(li);
	}



	static function createFieldValuesRender(ei:data.inst.EntityInstance, fi:data.inst.FieldInstance) {
		var font = Assets.fontPixel;

		var valuesFlow = new h2d.Flow();
		valuesFlow.layout = Horizontal;
		valuesFlow.verticalAlign = Middle;

		// Array opening
		if( fi.def.isArray && fi.getArrayLength()>1 ) {
			var tf = new h2d.Text(font, valuesFlow);
			tf.textColor = ei.getSmartColor(true);
			tf.text = "[";
			tf.scale(FIELD_TEXT_SCALE);
		}

		for( idx in 0...fi.getArrayLength() ) {
			if( !fi.valueIsNull(idx) && !( !fi.def.editorAlwaysShow && fi.def.type==F_Bool && fi.isUsingDefault(idx) ) ) {
				if( fi.hasIconForDisplay(idx) ) {
					// Icon
					var w = new h2d.Flow(valuesFlow);
					var tile = fi.getIconForDisplay(idx);
					var bmp = new h2d.Bitmap( tile, w );
					var s = M.fmin(1, M.fmin( ei.def.width/ tile.width, ei.def.height/tile.height ));
					bmp.setScale(s);
				}
				else if( fi.def.type==F_Color ) {
					// Color disc
					var g = new h2d.Graphics(valuesFlow);
					var r = 6;
					g.beginFill( fi.getColorAsInt(idx) );
					g.lineStyle(1, 0x0, 0.8);
					g.drawCircle(r,r,r, 16);
				}
				else {
					// Text render
					var tf = new h2d.Text(font, valuesFlow);
					tf.textColor = ei.getSmartColor(true);
					tf.filter = new dn.heaps.filter.PixelOutline();
					tf.maxWidth = 300;
					tf.scale(FIELD_TEXT_SCALE);
					var v = fi.getForDisplay(idx);
					if( fi.def.type==F_Bool && fi.def.editorDisplayMode==ValueOnly )
						tf.text = '${fi.getBool(idx)?"+":"-"}${fi.def.identifier}';
					else
						tf.text = v;
				}
			}

			// Array separator
			if( fi.def.isArray && idx<fi.getArrayLength()-1 ) {
				var tf = new h2d.Text(font, valuesFlow);
				tf.textColor = ei.getSmartColor(true);
				tf.text = ",";
				tf.scale(FIELD_TEXT_SCALE);
			}
		}

		// Array closing
		if( fi.def.isArray && fi.getArrayLength()>1 ) {
			var tf = new h2d.Text(font, valuesFlow);
			tf.textColor = ei.getSmartColor(true);
			tf.text = "]";
			tf.scale(FIELD_TEXT_SCALE);
		}

		return valuesFlow;
	}

	static inline function dashedLine(g:h2d.Graphics, fx:Float, fy:Float, tx:Float, ty:Float, dashLen=4.) {
		var a = Math.atan2(ty-fy, tx-fx);
		var len = M.dist(fx,fy, tx,ty);
		var cur = 0.;
		var count = M.ceil( len/(dashLen*2) );
		var dashLen = len / ( count%2==0 ? count+1 : count );

		while( cur<len ) {
			g.moveTo( fx+Math.cos(a)*cur, fy+Math.sin(a)*cur );
			g.lineTo( fx+Math.cos(a)*(cur+dashLen), fy+Math.sin(a)*(cur+dashLen) );
			cur+=dashLen*2;
		}
	}

	public static function createEntityRender(?ei:data.inst.EntityInstance, ?def:data.def.EntityDef, ?li:data.inst.LayerInstance, ?parent:h2d.Object) {
		if( def==null && ei==null )
			throw "Need at least 1 parameter";

		if( def==null )
			def = ei.def;

		// Init
		var wrapper = new h2d.Object(parent);

		var g = new h2d.Graphics(wrapper);
		g.x = Std.int( -def.width*def.pivotX );
		g.y = Std.int( -def.height*def.pivotY );

		// Render a tile
		function renderTile(tilesetId:Null<Int>, tileId:Null<Int>, mode:data.DataTypes.EntityTileRenderMode) {
			if( tileId==null || tilesetId==null ) {
				// Missing tile
				var p = 2;
				g.lineStyle(3, 0xff0000);
				g.moveTo(p,p);
				g.lineTo(def.width-p, def.height-p);
				g.moveTo(def.width-p, p);
				g.lineTo(p, def.height-p);
			}
			else {
				g.beginFill(def.color, 0.2);
				g.drawRect(0, 0, def.width, def.height);

				var td = Editor.ME.project.defs.getTilesetDef(tilesetId);
				var t = td.getTile(tileId);
				var bmp = new h2d.Bitmap(t, wrapper);
				switch mode {
					case Stretch:
						bmp.scaleX = def.width / bmp.tile.width;
						bmp.scaleY = def.height / bmp.tile.height;

					case Crop:
						if( bmp.tile.width>def.width || bmp.tile.height>def.height )
							bmp.tile = bmp.tile.sub(
								0, 0,
								M.fmin( bmp.tile.width, def.width ),
								M.fmin( bmp.tile.height, def.height )
							);
				}
				bmp.tile.setCenterRatio(def.pivotX, def.pivotY);
			}
		}

		// Base render
		var custTile = ei==null ? null : ei.getSmartTile();
		if( custTile!=null )
			renderTile(custTile.tilesetUid, custTile.tileId, Stretch);
		else
			switch def.renderMode {
			case Rectangle, Ellipse:
				g.beginFill(def.color);
				g.lineStyle(1, 0x0, 0.4);
				switch def.renderMode {
					case Rectangle:
						g.drawRect(0, 0, def.width, def.height);

					case Ellipse:
						g.drawEllipse(def.width*0.5, def.height*0.5, def.width*0.5, def.height*0.5, 0, def.width<=16 || def.height<=16 ? 16 : 0);

					case _:
				}
				g.endFill();

			case Cross:
				g.lineStyle(5, def.color, 1);
				g.moveTo(0,0);
				g.lineTo(def.width, def.height);
				g.moveTo(0,def.height);
				g.lineTo(def.width, 0);

			case Tile:
				renderTile(def.tilesetId, def.tileId, def.tileRenderMode);
			}

		// Pivot
		g.beginFill(def.color);
		g.lineStyle(1, 0x0, 0.5);
		var pivotSize = 3;
		g.drawRect(
			Std.int((def.width-pivotSize)*def.pivotX),
			Std.int((def.height-pivotSize)*def.pivotY),
			pivotSize, pivotSize
		);


		function _addBg(f:h2d.Flow, dark:Float) {
			var bg = new h2d.ScaleGrid(Assets.elements.getTile("fieldBg"), 2,2);
			f.addChildAt(bg, 0);
			f.getProperties(bg).isAbsolute = true;
			bg.color.setColor( C.addAlphaF( C.toBlack( ei.getSmartColor(false), dark ) ) );
			bg.alpha = 0.8;
			bg.x = -2;
			bg.y = 1;
			bg.width = f.outerWidth + M.fabs(bg.x)*2;
			bg.height = f.outerHeight;
		}

		// Display fields not marked as "Hidden"
		if( ei!=null && li!=null ) {
			// Init field wrappers
			var font = Assets.fontPixel;

			var custom = new h2d.Graphics(wrapper);

			var above = new h2d.Flow(wrapper);
			above.layout = Vertical;
			above.horizontalAlign = Middle;
			above.verticalSpacing = 1;

			var center = new h2d.Flow(wrapper);
			center.layout = Vertical;
			center.horizontalAlign = Middle;
			center.verticalSpacing = 1;

			var beneath = new h2d.Flow(wrapper);
			beneath.layout = Vertical;
			beneath.horizontalAlign = Middle;
			beneath.verticalSpacing = 1;

			// Attach fields
			for(fd in ei.def.fieldDefs) {
				var fi = ei.getFieldInstance(fd);

				// Value error
				var err = fi.getFirstErrorInValues();
				if( err!=null ) {
					var tf = new h2d.Text(font, above);
					tf.textColor = 0xffcc00;
					tf.text = '<$err>';
				}

				// Skip hiddens
				if( fd.editorDisplayMode==Hidden )
					continue;

				if( !fi.def.editorAlwaysShow && ( fi.def.isArray && fi.getArrayLength()==0 || !fi.def.isArray && fi.isUsingDefault(0) ) )
					continue;

				// Position
				var fieldWrapper = new h2d.Flow();
				switch fd.editorDisplayPos {
					case Above: above.addChild(fieldWrapper);
					case Center: center.addChild(fieldWrapper);
					case Beneath: beneath.addChild(fieldWrapper);
				}

				switch fd.editorDisplayMode {
					case Hidden: // N/A

					case NameAndValue:
						var f = new h2d.Flow(fieldWrapper);
						f.verticalAlign = Middle;

						var tf = new h2d.Text(font, f);
						tf.textColor = ei.getSmartColor(true);
						tf.text = fd.identifier+" = ";
						tf.scale(FIELD_TEXT_SCALE);
						tf.filter = new dn.heaps.filter.PixelOutline();

						f.addChild( createFieldValuesRender(ei,fi) );

					case ValueOnly:
						fieldWrapper.addChild( createFieldValuesRender(ei,fi) );

					case RadiusPx:
						custom.lineStyle(1, ei.getSmartColor(false), 0.33);
						custom.drawCircle(0,0, fi.def.type==F_Float ? fi.getFloat(0) : fi.getInt(0));

					case RadiusGrid:
						custom.lineStyle(1, ei.getSmartColor(false), 0.33);
						custom.drawCircle(0,0, ( fi.def.type==F_Float ? fi.getFloat(0) : fi.getInt(0) ) * li.def.gridSize);

					case EntityTile:

					case PointStar, PointPath:
						var fx = ei.getCellCenterX(li.def);
						var fy = ei.getCellCenterY(li.def);
						custom.lineStyle(1, ei.getSmartColor(false), 0.66);

						for(i in 0...fi.getArrayLength()) {
							var pt = fi.getPointGrid(i);
							if( pt==null )
								continue;

							var tx = M.round( (pt.cx+0.5)*li.def.gridSize-ei.x );
							var ty = M.round( (pt.cy+0.5)*li.def.gridSize-ei.y );
							dashedLine(custom, fx,fy, tx,ty, 3);
							custom.drawRect( tx-2, ty-2, 4, 4 );

							if( fd.editorDisplayMode==PointPath ) {
								fx = tx;
								fy = ty;
							}
						}
				}

				// Field bg
				var needBg = switch fd.type {
					case F_Int, F_Float:
						switch fd.editorDisplayMode {
							case RadiusPx, RadiusGrid: false;
							case _: true;
						};
					case F_String, F_Text, F_Bool, F_Path: true;
					case F_Color, F_Point: false;
					case F_Enum(enumDefUid): fd.editorDisplayMode!=EntityTile;
				}

				if( needBg )
					_addBg(fieldWrapper, 0.15);

				fieldWrapper.visible = fieldWrapper.numChildren>0;

			}

			// Identifier label
			if( ei.def.showName ) {
				var f = new h2d.Flow(above);
				var tf = new h2d.Text(Assets.fontPixel, f);
				tf.textColor = ei.getSmartColor(true);
				tf.text = def.identifier.substr(0,16);
				tf.scale(0.5);
				tf.x = Std.int( def.width*0.5 - tf.textWidth*tf.scaleX*0.5 );
				tf.y = 0;
				tf.filter = new dn.heaps.filter.PixelOutline();
				_addBg(f, 0.5);
			}

			// Update wrappers pos
			above.x = Std.int( -def.width*def.pivotX - above.outerWidth*0.5 + def.width*0.5 );
			above.y = Std.int( -above.outerHeight - def.height*def.pivotY - 1 );

			center.x = Std.int( -def.width*def.pivotX - center.outerWidth*0.5 + def.width*0.5 );
			center.y = Std.int( -def.height*def.pivotY - center.outerHeight*0.5 + def.height*0.5);

			beneath.x = Std.int( -def.width*def.pivotX - beneath.outerWidth*0.5 + def.width*0.5 );
			beneath.y = Std.int( def.height*(1-def.pivotY) + 1 );
		}

		return wrapper;
	}

	function applyLayerVisibility(li:data.inst.LayerInstance) {
		var wrapper = layerRenders.get(li.layerDefUid);
		if( wrapper==null )
			return;

		wrapper.visible = isLayerVisible(li);
		wrapper.alpha = li.def.displayOpacity * ( !settings.singleLayerMode || li==editor.curLayerInstance ? 1 : 0.2 );
		wrapper.filter = !settings.singleLayerMode || li==editor.curLayerInstance ? null : new h2d.filter.Group([
			C.getColorizeFilterH2d(0x8c99c1, 0.9),
			new h2d.filter.Blur(2),
		]);
	}

	@:allow(page.Editor)
	function applyAllLayersVisibility() {
		for(ld in editor.project.defs.layers) {
			var li = editor.curLevel.getLayerInstance(ld);
			applyLayerVisibility(li);
		}
	}

	public inline function invalidateLayer(?li:data.inst.LayerInstance, ?layerDefUid:Int) {
		if( li==null )
			li = editor.curLevel.getLayerInstance(layerDefUid);
		layerInvalidations.set( li.layerDefUid, { left:0, right:li.cWid-1, top:0, bottom:li.cHei-1 } );

		if( li.def.type==IntGrid )
			for(l in editor.curLevel.layerInstances)
				if( l.def.type==AutoLayer && l.def.autoSourceLayerDefUid==li.def.uid )
					invalidateLayer(l);
	}

	public inline function invalidateLayerArea(li:data.inst.LayerInstance, left:Int, right:Int, top:Int, bottom:Int) {
		if( layerInvalidations.exists(li.layerDefUid) ) {
			var bounds = layerInvalidations.get(li.layerDefUid);
			bounds.left = M.imin(bounds.left, left);
			bounds.right = M.imax(bounds.right, right);
		}
		else
			layerInvalidations.set( li.layerDefUid, { left:left, right:right, top:top, bottom:bottom } );

		// Invalidate linked auto-layers
		if( li.def.type==IntGrid )
			for(other in editor.curLevel.layerInstances)
				if( other.def.type==AutoLayer && other.def.autoSourceLayerDefUid==li.layerDefUid )
					invalidateLayerArea(other, left, right, top, bottom);
	}

	public inline function invalidateUi() {
		uiInvalidated = true;
	}

	public inline function invalidateAll() {
		allInvalidated = true;
	}

	override function postUpdate() {
		super.postUpdate();

		// Fade-out temporary rects
		var i = 0;
		while( i<rectBleeps.length ) {
			var o = rectBleeps[i];
			o.alpha-=tmod*0.042;
			o.setScale( 1 + 0.2 * (1-o.alpha) );
			if( o.alpha<=0 ) {
				o.remove();
				rectBleeps.splice(i,1);
			}
			else
				i++;
		}


		// Render invalidation system
		if( allInvalidated ) {
			// Full
			renderAll();
			App.LOG.warning("Full render requested");
		}
		else {
			// UI & bg elements
			if( uiInvalidated ) {
				renderBg();
				renderBounds();
				renderGrid();
				uiInvalidated = false;
				App.LOG.render("Rendered level UI");
			}

			// Layers
			for( li in editor.curLevel.layerInstances )
				if( layerInvalidations.exists(li.layerDefUid) ) {
					var b = layerInvalidations.get(li.layerDefUid);
					if( li.def.isAutoLayer() )
						li.applyAllAutoLayerRulesAt( b.left, b.top, b.right-b.left+1, b.bottom-b.top+1 );
					renderLayer(li);
				}
		}

		applyGridVisibility();
	}

}
