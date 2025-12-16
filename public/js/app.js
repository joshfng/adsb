// ADS-B Flight Tracker Frontend

// HTML escape helper to prevent XSS
function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  const div = document.createElement('div');
  div.textContent = String(str);
  return div.innerHTML;
}

class ADSBTracker {
  constructor() {
    this.map = null;
    this.markers = {};
    this.trails = {};
    this.aircraft = {};
    this.selectedAircraft = null;
    this.messageCount = 0;
    this.ws = null;
    this.statsInterval = null;
    this.receiverLocation = null;
    this.rangeRings = [];
    this.receiverMarker = null;

    // Display toggles
    this.showTrails = true;
    this.showLabels = false;
    this.showRangeRings = true;
    this.showHeatmap = false;
    this.heatmapLayer = null;
    this.heatmapData = [];
    this.historyStatsInterval = null;

    // Sound alerts
    this.soundEnabled = false;
    this.trackedAircraft = new Set(); // ICAOs to track
    this.trackedCallsigns = new Set(); // Callsigns to track
    this.alertedEmergencies = new Set(); // Already alerted emergencies
    this.lastAlertTime = 0;

    // Push notifications
    this.notificationsEnabled = false;
    this.notificationPermission = 'default';

    // Alert settings
    this.alertOnMilitary = true;
    this.alertOnPolice = true;
    this.alertOnEmergency = true;

    // UI update throttling
    this.listUpdatePending = false;
    this.listUpdateTimeout = null;
    this.hoveredIcao = null;

    // Feed status
    this.feedStatus = null;
    this.feedStatusInterval = null;

    // Filters
    this.filters = {
      minAltitude: 0,
      maxAltitude: 50000,
      searchText: '',
      showMilitary: true,
      showPolice: true,
      onlyMilitary: false,
      onlyPolice: false,
      aircraftType: 'all',  // 'all', 'helicopter', 'jet', 'prop'
      positionOnly: false,
      sortBy: 'callsign'  // callsign, altitude, distance, signal
    };

    // Map layers
    this.baseLayers = {};
    this.currentLayer = null;

    // Known law enforcement aircraft (Ohio area)
    // Add ICAO hex codes of known police/sheriff aircraft
    this.lawEnforcementIcaos = new Set([
      // Ohio State Highway Patrol / Dept of Public Safety
      'A03815',  // N113HP - Cessna 206
      'A05216',  // N12HP - Cessna 206
      'A11791',  // N17HP - Cessna 206
      'A13F10',  // N18HP - Cessna 206
      'A1668F',  // N19HP - Cessna 206
      'A34B45',  // N311HP - Cessna 206
      'A67108',  // N514HP - Cessna 206
      'A88B1E',  // N65HP - Gippsland GA8
      'A7C34A',  // N6HP - Cessna 206
      'A98F5D',  // N715HP - Cessna 206
      'A996CB',  // N717HP - Cessna 208B (2024)
      'A97A71',  // N71HP - Airbus H125 helicopter
      'A9A1F0',  // N72HP - Airbus H125 helicopter
      'A9C96F',  // N73HP - Eurocopter AS350 helicopter
      'AC9768',  // N910HP - Cessna 206

      // Cleveland Division of Police
      'AA5812',  // N766CP - Cessna 172
      'AD389E',  // N951CP - MD 530F helicopter
      'AD3C55',  // N952CP - MD 530F helicopter

      // Columbus Division of Police
      'A70AD0',  // N553CP - MD 369FF helicopter
      'A715F5',  // N556CP - MD 369FF helicopter
      'A719AC',  // N557CP - MD 369FF helicopter

      // Ohio County Sheriffs
      'A69164',  // N522LP - Guernsey County Sheriff
      'A74523',  // N568FD - Highland County Sheriff
      'A85230',  // N635VF - Highland County Sheriff
      'A94C41',  // N699BC - Butler County Sheriff (helicopter)
      'A9EC57',  // N7389A - Auglaize County Sheriff

      // Ohio Municipal Police
      'A6EBC8',  // N545PD - Euclid Police Department
      'AC9C59',  // N911WC - Montpelier Police Department
    ]);

    // Nearby airports data
    this.airports = [
      { code: 'CAK', name: 'Akron-Canton Airport', lat: 40.9161, lon: -81.4422, type: 'major' },
      { code: 'CLE', name: 'Cleveland Hopkins Intl', lat: 41.4117, lon: -81.8498, type: 'major' },
      { code: 'AKR', name: 'Akron Fulton Intl', lat: 41.0375, lon: -81.4669, type: 'general' },
      { code: 'YNG', name: 'Youngstown-Warren Regional', lat: 41.2607, lon: -80.6789, type: 'regional' },
      { code: 'PIT', name: 'Pittsburgh Intl', lat: 40.4915, lon: -80.2329, type: 'major' },
      { code: 'CGF', name: 'Cuyahoga County Airport', lat: 41.5651, lon: -81.4864, type: 'general' },
      { code: 'LNN', name: 'Lost Nation Airport', lat: 41.6840, lon: -81.3897, type: 'general' },
      { code: 'BKL', name: 'Burke Lakefront Airport', lat: 41.5175, lon: -81.6833, type: 'regional' },
      { code: 'MFD', name: 'Mansfield Lahm Regional', lat: 40.8214, lon: -82.5166, type: 'regional' },
      { code: '1G5', name: 'Medina Municipal', lat: 41.1313, lon: -81.7649, type: 'general' },
      { code: 'PHD', name: 'Harry Clever Field', lat: 40.4709, lon: -81.4197, type: 'general' },
    ];

    // Military ICAO prefix ranges (US military aircraft)
    // US civil: A00001-ADF7C7, Military: ADF7C8+ (AE, AF ranges)
    this.militaryIcaoPrefixes = [
      'AE', 'AF',  // US Air Force / Military
    ];

    // Military callsign patterns (specific patterns only to avoid false positives)
    this.militaryPatterns = [
      /^REACH\d/i,  // USAF Air Mobility Command (REACH followed by number)
      /^RCH\d/i,    // USAF AMC short
      /^EVAC\d/i,   // Medical evacuation
      /^DUKE\d/i,   // C-12 transport
      /^KING\d/i,   // HC-130 SAR
      /^PEDRO\d/i,  // HH-60 rescue
      /^JOLLY\d/i,  // HH-60 rescue
      /^ARMY\d/i,   // US Army
      /^NAVY\d/i,   // US Navy
      /^TOPCAT/i,   // F-35
      /^VIPER\d/i,  // F-16
      /^BONE\d/i,   // B-1 Bomber
      /^DEATH\d/i,  // B-2
      /^SENTRY\d/i, // AWACS
      /^DOOM\d/i,   // F-22
      /^RAID\d/i,   // Tankers
      /^SHELL\d/i,  // Tankers
      /^PACK\d/i,   // Tankers
      /^TEAL\d/i,   // KC-135
      /^RAPTOR\d/i, // F-22
      /^WARTHOG/i,  // A-10
      /^HOG\d/i,    // A-10
      /^THUD\d/i,   // A-10
      /^MOOSE\d/i,  // C-17
      /^HERKY\d/i,  // C-130
      /^SPOOKY/i,   // AC-130
      /^OMNI\d/i,   // E-3 AWACS
      /^DRAGN\d/i,  // U-2
      /^SPAR\d/i,   // VIP/Government
      /^SAM\d+$/i,  // Special Air Mission (SAM followed by numbers only)
      /^VENUS\d/i,  // WC-135
      /^CGNR\d/i,   // Coast Guard
      /^USCG/i,     // Coast Guard
    ];

    // Known military ICAO hex codes (Ohio area bases)
    this.militaryIcaos = new Set([
      // Add known military aircraft ICAO codes as discovered
    ]);

    // Law enforcement callsign patterns
    this.lawEnforcementPatterns = [
      /^POLICE/i,
      /^POL\d/i,
      /^TROOPER/i,
      /^SHERIFF/i,
      /^COPTER/i,
      /^OSP/i,         // Ohio State Patrol
      /^OHP/i,         // Ohio Highway Patrol
      /^OHSP/i,
      /^N\d*HP$/i,     // Ohio Highway Patrol N-numbers (N71HP, N72HP, etc)
      /^N\d+PD$/i,     // N-numbers ending in PD (Police Dept)
      /^N\d+SP$/i,     // N-numbers ending in SP (State Police)
      /^N\d+CP$/i,     // N-numbers ending in CP (City Police - Columbus, Cleveland)
      /^N\d+LP$/i,     // N-numbers ending in LP (Law enforcement)
      /^CBP/i,         // Customs & Border Protection
      /^BADGE/i,
      /^PATROL/i,
      /^SWAT/i,
      /^OMVI/i,        // Ohio DUI enforcement flights
      /^ENFORCER/i,
      /^GUARDIAN/i,
      /^HAWK/i,        // Common police helicopter callsign
    ];

    this.init();
  }

  init() {
    this.loadSettings();
    this.initMap();
    this.addAirportMarkers();
    this.initWebSocket();
    this.initKeyboardShortcuts();
    this.startStatsPolling();
    this.startHistoryStatsPolling();
    this.startFeedStatusPolling();
    this.initNotifications();
  }

  loadSettings() {
    try {
      const saved = localStorage.getItem('adsb-settings');
      if (saved) {
        const settings = JSON.parse(saved);
        this.showTrails = settings.showTrails ?? true;
        this.showLabels = settings.showLabels ?? false;
        this.showRangeRings = settings.showRangeRings ?? true;
        this.soundEnabled = settings.soundEnabled ?? false;
        this.notificationsEnabled = settings.notificationsEnabled ?? false;
        this.alertOnMilitary = settings.alertOnMilitary ?? true;
        this.alertOnPolice = settings.alertOnPolice ?? true;
        this.alertOnEmergency = settings.alertOnEmergency ?? true;
        this.trackedAircraft = new Set(settings.trackedAircraft || []);
        this.trackedCallsigns = new Set(settings.trackedCallsigns || []);
        this.filters = { ...this.filters, ...settings.filters };
      }
    } catch (e) {
      console.warn('Failed to load settings:', e.message);
    }
  }

  saveSettings() {
    try {
      localStorage.setItem('adsb-settings', JSON.stringify({
        showTrails: this.showTrails,
        showLabels: this.showLabels,
        showRangeRings: this.showRangeRings,
        soundEnabled: this.soundEnabled,
        notificationsEnabled: this.notificationsEnabled,
        alertOnMilitary: this.alertOnMilitary,
        alertOnPolice: this.alertOnPolice,
        alertOnEmergency: this.alertOnEmergency,
        trackedAircraft: Array.from(this.trackedAircraft),
        trackedCallsigns: Array.from(this.trackedCallsigns),
        filters: this.filters
      }));
    } catch (e) {
      console.warn('Failed to save settings:', e.message);
    }
  }

  initMap() {
    // Default to Akron/Canton, Ohio area
    this.map = L.map('map', {
      center: [40.9161, -81.4422],
      zoom: 9,
      zoomControl: true,
    });

    // Define base layers
    this.baseLayers = {
      'Streets': L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap',
        maxZoom: 19,
      }),
      'Satellite': L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
        attribution: '&copy; Esri',
        maxZoom: 19,
      }),
      'Dark': L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        attribution: '&copy; CartoDB',
        maxZoom: 19,
      })
    };

    // Add default layer
    const savedLayer = localStorage.getItem('adsb-map-layer') || 'Dark';
    this.baseLayers[savedLayer].addTo(this.map);
    this.currentLayer = savedLayer;

    // Add layer control
    L.control.layers(this.baseLayers, null, { position: 'topright' }).addTo(this.map);

    // Save layer preference on change
    this.map.on('baselayerchange', (e) => {
      localStorage.setItem('adsb-map-layer', e.name);
      this.currentLayer = e.name;
    });

    // Set receiver location to Canton-Akron Airport (CAK)
    this.receiverLocation = { lat: 40.9161, lon: -81.4422 };
    this.addReceiverMarker();
    this.addRangeRings();

    // Optionally update to actual location if available
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          this.receiverLocation = {
            lat: position.coords.latitude,
            lon: position.coords.longitude
          };
          this.addReceiverMarker();
          this.addRangeRings();
        },
        () => {
          console.log('Using default Canton-Akron Airport location');
        }
      );
    }
  }

  addReceiverMarker() {
    if (!this.receiverLocation) return;

    const icon = L.divIcon({
      className: 'receiver-marker',
      html: `<div class="receiver-icon"></div>`,
      iconSize: [16, 16],
      iconAnchor: [8, 8],
    });

    this.receiverMarker = L.marker(
      [this.receiverLocation.lat, this.receiverLocation.lon],
      { icon, zIndexOffset: -1000 }
    ).addTo(this.map).bindPopup('Receiver Location');
  }

  addRangeRings() {
    if (!this.receiverLocation) return;

    // Clear existing rings
    this.rangeRings.forEach(ring => this.map.removeLayer(ring));
    this.rangeRings = [];

    if (!this.showRangeRings) return;

    const distances = [50, 100, 150, 200]; // nautical miles
    const nmToMeters = 1852;

    distances.forEach(nm => {
      const ring = L.circle(
        [this.receiverLocation.lat, this.receiverLocation.lon],
        {
          radius: nm * nmToMeters,
          color: '#e94560',
          weight: 1,
          opacity: 0.4,
          fill: false,
          dashArray: '5, 10'
        }
      ).addTo(this.map);

      // Add label
      const label = L.marker(
        [this.receiverLocation.lat + (nm * nmToMeters / 111000), this.receiverLocation.lon],
        {
          icon: L.divIcon({
            className: 'range-label',
            html: `<span>${nm} nm</span>`,
            iconSize: [50, 20],
            iconAnchor: [25, 10]
          })
        }
      ).addTo(this.map);

      this.rangeRings.push(ring, label);
    });
  }

  addAirportMarkers() {
    this.airports.forEach(airport => {
      const iconClass = `airport-marker airport-${airport.type}`;
      const icon = L.divIcon({
        className: iconClass,
        html: `<div class="airport-icon">${airport.code}</div>`,
        iconSize: [40, 20],
        iconAnchor: [20, 10],
      });

      const marker = L.marker([airport.lat, airport.lon], {
        icon,
        zIndexOffset: -500
      }).addTo(this.map);

      marker.bindPopup(`
        <strong>${airport.code}</strong><br>
        ${airport.name}<br>
        <small>Type: ${airport.type}</small>
      `);
    });
  }

  initWebSocket() {
    // Use ActionCable for WebSocket connection
    const self = this;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 10;
    this.reconnectTimeout = null;

    // Check if ActionCable is available
    if (typeof ActionCable === 'undefined') {
      console.error('ActionCable not loaded, falling back to polling');
      this.updateStatus('Polling', 'running');
      return;
    }

    this.cable = ActionCable.createConsumer();
    this.subscription = this.cable.subscriptions.create("AircraftChannel", {
      connected() {
        console.log('ActionCable connected');
        self.reconnectAttempts = 0;
        if (self.reconnectTimeout) {
          clearTimeout(self.reconnectTimeout);
          self.reconnectTimeout = null;
        }
        self.updateStatus('Receiving', 'running');
      },

      disconnected() {
        console.log('ActionCable disconnected');
        self.updateStatus('Disconnected', 'disconnected');
        self.scheduleReconnect();
      },

      rejected() {
        console.error('ActionCable subscription rejected');
        self.updateStatus('Rejected', 'disconnected');
      },

      received(data) {
        self.handleMessage(data);
      },

      // Request aircraft list
      getAircraft() {
        this.perform('get_aircraft');
      }
    });
  }

  scheduleReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('Max reconnection attempts reached');
      this.updateStatus('Failed', 'disconnected');
      return;
    }

    this.reconnectAttempts++;
    // Exponential backoff: 1s, 2s, 4s, 8s... max 30s
    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts - 1), 30000);
    console.log(`Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`);
    this.updateStatus(`Reconnecting (${this.reconnectAttempts})`, 'disconnected');

    this.reconnectTimeout = setTimeout(() => {
      if (this.cable && this.cable.connection) {
        this.cable.connection.reopen();
      }
    }, delay);
  }

  initKeyboardShortcuts() {
    document.addEventListener('keydown', (e) => {
      // Ignore if typing in an input
      if (e.target.tagName === 'INPUT') return;

      switch (e.key.toLowerCase()) {
        case 't':
          this.toggleTrails();
          break;
        case 'l':
          this.toggleLabels();
          break;
        case 'r':
          this.toggleRangeRings();
          break;
        case 's':
          this.toggleSound();
          break;
        case 'n':
          this.toggleNotifications();
          break;
        case 'm':
          this.toggleMilitaryAlerts();
          break;
        case 'p':
          this.togglePoliceAlerts();
          break;
        case 'f':
          this.focusFilter();
          break;
        case 'escape':
          this.clearSelection();
          break;
        case '+':
        case '=':
          this.map.zoomIn();
          break;
        case '-':
          this.map.zoomOut();
          break;
      }
    });
  }

  toggleTrails() {
    this.showTrails = !this.showTrails;
    this.saveSettings();
    Object.keys(this.trails).forEach(icao => {
      if (this.showTrails) {
        this.trails[icao].addTo(this.map);
      } else {
        this.map.removeLayer(this.trails[icao]);
      }
    });
    this.showNotification(`Trails ${this.showTrails ? 'ON' : 'OFF'}`);
  }

  toggleLabels() {
    this.showLabels = !this.showLabels;
    this.saveSettings();
    // Re-render all markers
    Object.values(this.aircraft).forEach(ac => this.updateMarker(ac));
    this.showNotification(`Labels ${this.showLabels ? 'ON' : 'OFF'}`);
  }

  toggleRangeRings() {
    this.showRangeRings = !this.showRangeRings;
    this.saveSettings();
    this.addRangeRings();
    this.showNotification(`Range rings ${this.showRangeRings ? 'ON' : 'OFF'}`);
  }

  focusFilter() {
    const input = document.getElementById('filterSearch');
    if (input) input.focus();
  }

  clearSelection() {
    this.selectedAircraft = null;
    document.getElementById('infoPanel').classList.add('hidden');
    this.updateAircraftListUI();
  }

  showNotification(text) {
    let notif = document.getElementById('notification');
    if (!notif) {
      notif = document.createElement('div');
      notif.id = 'notification';
      document.body.appendChild(notif);
    }
    notif.textContent = text;
    notif.classList.add('show');
    setTimeout(() => notif.classList.remove('show'), 1500);
  }

  handleMessage(data) {
    switch (data.type) {
      case 'aircraft_update':
        this.updateAircraft(data.aircraft);
        this.messageCount++;
        this.updateMessageCount();
        break;

      case 'aircraft_list':
        this.updateAircraftList(data.aircraft);
        break;
    }
  }

  updateAircraft(aircraft) {
    const icao = aircraft.icao;
    this.aircraft[icao] = aircraft;

    if (this.passesFilter(aircraft)) {
      this.updateMarker(aircraft);
      this.updateTrail(aircraft);
    }
    this.scheduleListUpdate();
    this.updateAircraftCount();

    // Check for alerts (emergency squawks, tracked aircraft)
    this.checkAlerts(aircraft);

    if (this.selectedAircraft === icao) {
      this.updateInfoPanel(aircraft);
    }
  }

  updateAircraftList(aircraftList) {
    const currentIcaos = new Set(aircraftList.map(ac => ac.icao));

    // Update aircraft data
    aircraftList.forEach((ac) => {
      this.aircraft[ac.icao] = ac;
      if (this.passesFilter(ac)) {
        this.updateMarker(ac);
        this.updateTrail(ac);
      }
    });

    // Remove stale markers and trails
    Object.keys(this.markers).forEach((icao) => {
      if (!currentIcaos.has(icao)) {
        this.map.removeLayer(this.markers[icao]);
        delete this.markers[icao];
        if (this.trails[icao]) {
          this.map.removeLayer(this.trails[icao]);
          delete this.trails[icao];
        }
        delete this.aircraft[icao];
      }
    });

    this.scheduleListUpdate();
    this.updateAircraftCount();
  }

  passesFilter(aircraft) {
    const { minAltitude, maxAltitude, searchText, positionOnly,
            showMilitary, showPolice, onlyMilitary, onlyPolice, aircraftType } = this.filters;

    if (positionOnly && (aircraft.latitude == null || aircraft.longitude == null)) {
      return false;
    }

    if (aircraft.altitude != null) {
      if (aircraft.altitude < minAltitude || aircraft.altitude > maxAltitude) {
        return false;
      }
    }

    if (searchText) {
      const search = searchText.toLowerCase();
      const callsign = (aircraft.callsign || '').toLowerCase();
      const icao = aircraft.icao.toLowerCase();
      if (!callsign.includes(search) && !icao.includes(search)) {
        return false;
      }
    }

    // Type filters
    const isMil = this.isMilitary(aircraft);
    const isPol = this.isLawEnforcement(aircraft);
    const category = this.getAircraftCategory(aircraft);

    // "Only" filters take priority - if enabled, only show matching aircraft
    if (onlyMilitary && !isMil) {
      return false;
    }
    if (onlyPolice && !isPol) {
      return false;
    }

    // Hide filters - if disabled, hide matching aircraft
    if (!showMilitary && isMil) {
      return false;
    }
    if (!showPolice && isPol) {
      return false;
    }

    // Aircraft type filter
    if (aircraftType !== 'all' && category !== aircraftType) {
      return false;
    }

    return true;
  }

  updateTrail(aircraft) {
    const { icao, position_history } = aircraft;

    if (!position_history || position_history.length < 2) {
      return;
    }

    const points = position_history
      .filter(p => p.lat && p.lon)
      .map(p => [p.lat, p.lon]);

    if (points.length < 2) return;

    // Create gradient colors based on altitude
    const colors = position_history.map(p => this.altitudeColor(p.alt));

    if (this.trails[icao]) {
      this.trails[icao].setLatLngs(points);
    } else {
      const trail = L.polyline(points, {
        color: this.altitudeColor(aircraft.altitude),
        weight: 4,
        opacity: 0.9,
        smoothFactor: 1
      });

      if (this.showTrails) {
        trail.addTo(this.map);
      }
      this.trails[icao] = trail;
    }

    // Update trail color based on current altitude
    this.trails[icao].setStyle({ color: this.altitudeColor(aircraft.altitude) });
  }

  altitudeColor(alt) {
    if (alt == null) return '#888';
    if (alt < 10000) return '#00ff00';  // Green - low
    if (alt < 20000) return '#88ff00';  // Yellow-green
    if (alt < 30000) return '#ffff00';  // Yellow
    if (alt < 40000) return '#ff8800';  // Orange
    return '#ff0000';  // Red - high
  }

  isLawEnforcement(aircraft) {
    // Check known ICAO addresses
    if (this.lawEnforcementIcaos.has(aircraft.icao.toUpperCase())) {
      return true;
    }

    // Check callsign patterns
    const callsign = aircraft.callsign || '';
    for (const pattern of this.lawEnforcementPatterns) {
      if (pattern.test(callsign)) {
        return true;
      }
    }

    return false;
  }

  isMilitary(aircraft) {
    const icao = aircraft.icao.toUpperCase();

    // Check known military ICAO addresses
    if (this.militaryIcaos.has(icao)) {
      return true;
    }

    // Check military ICAO prefixes (US military allocations)
    for (const prefix of this.militaryIcaoPrefixes) {
      if (icao.startsWith(prefix)) {
        return true;
      }
    }

    // Check callsign patterns
    const callsign = aircraft.callsign || '';
    for (const pattern of this.militaryPatterns) {
      if (pattern.test(callsign)) {
        return true;
      }
    }

    return false;
  }

  getAircraftCategory(aircraft) {
    // Returns: 'helicopter', 'jet', 'prop', 'default'
    // This will be enhanced when we have FAA data in the frontend
    const callsign = (aircraft.callsign || '').toUpperCase();
    const icao = aircraft.icao.toUpperCase();

    // Check for helicopter indicators
    if (/COPTER|HELI|AIR\d+|MEDEVAC/i.test(callsign)) {
      return 'helicopter';
    }

    // Check for known helicopter law enforcement ICAOs
    const heliIcaos = ['A97A71', 'A9A1F0', 'A9C96F', 'AD389E', 'AD3C55', 'A70AD0', 'A715F5', 'A719AC', 'A94C41'];
    if (heliIcaos.includes(icao)) {
      return 'helicopter';
    }

    // Default based on altitude/speed heuristics
    // High altitude + high speed = likely jet
    if (aircraft.altitude > 25000 && aircraft.speed > 350) {
      return 'jet';
    }

    // Low altitude + slow speed = likely prop/GA
    if (aircraft.altitude < 10000 && aircraft.speed && aircraft.speed < 200) {
      return 'prop';
    }

    return 'default';
  }

  updateMarker(aircraft) {
    const { icao, latitude, longitude, heading, callsign, altitude } = aircraft;

    if (latitude == null || longitude == null) {
      // Remove marker and trail if no position
      if (this.markers[icao]) {
        this.map.removeLayer(this.markers[icao]);
        delete this.markers[icao];
      }
      if (this.trails[icao]) {
        this.map.removeLayer(this.trails[icao]);
        delete this.trails[icao];
      }
      return;
    }

    if (!this.passesFilter(aircraft)) {
      if (this.markers[icao]) {
        this.map.removeLayer(this.markers[icao]);
        delete this.markers[icao];
      }
      // Also remove trail when aircraft is filtered out
      if (this.trails[icao]) {
        this.map.removeLayer(this.trails[icao]);
        delete this.trails[icao];
      }
      return;
    }

    const rotation = heading || 0;
    const color = this.altitudeColor(altitude);
    const isSelected = this.selectedAircraft === icao;
    const isPolice = this.isLawEnforcement(aircraft);
    const isMilitary = this.isMilitary(aircraft);
    const category = this.getAircraftCategory(aircraft);

    const icon = L.divIcon({
      className: 'aircraft-marker',
      html: this.createAircraftIcon(rotation, color, isSelected, callsign, this.showLabels, isPolice, isMilitary, category),
      iconSize: [40, 40],
      iconAnchor: [20, 20],
    });

    if (this.markers[icao]) {
      this.markers[icao].setLatLng([latitude, longitude]);
      this.markers[icao].setIcon(icon);
    } else {
      const marker = L.marker([latitude, longitude], { icon })
        .addTo(this.map)
        .on('click', () => this.selectAircraft(icao));

      this.markers[icao] = marker;
    }

    const popupContent = `
      <strong>${callsign || icao}</strong><br>
      Altitude: ${altitude ? altitude.toLocaleString() + ' ft' : '--'}<br>
      Heading: ${heading ? heading + '°' : '--'}
    `;
    this.markers[icao].bindPopup(popupContent);
  }

  createAircraftIcon(rotation, color, isSelected, callsign, showLabel, isPolice = false, isMilitary = false, category = 'default') {
    const strokeColor = isSelected ? '#fff' : '#000';
    const strokeWidth = isSelected ? 2 : 1;
    const glow = `filter: drop-shadow(0 0 4px ${color}) drop-shadow(0 0 8px ${color});`;
    const label = showLabel && callsign ? `<div class="marker-label">${callsign}</div>` : '';

    // Badge priority: police > military
    let badge = '';
    if (isPolice) {
      badge = '<div class="police-badge">👮</div>';
    } else if (isMilitary) {
      badge = '<div class="military-badge">🎖️</div>';
    }

    // Get the appropriate SVG path for the aircraft category
    const svgPath = this.getAircraftSvgPath(category);

    return `
      <div class="marker-container">
        <svg width="40" height="40" viewBox="0 0 30 30" style="transform: rotate(${rotation}deg); ${glow}">
          ${svgPath.replace('FILL_COLOR', color).replace('STROKE_COLOR', strokeColor).replace('STROKE_WIDTH', strokeWidth)}
        </svg>
        ${badge}
        ${label}
      </div>
    `;
  }

  getAircraftSvgPath(category) {
    switch (category) {
      case 'helicopter':
        // Helicopter icon - rotor blade shape
        return `
          <circle cx="15" cy="15" r="4" fill="FILL_COLOR" stroke="STROKE_COLOR" stroke-width="STROKE_WIDTH"/>
          <line x1="15" y1="15" x2="15" y2="5" stroke="FILL_COLOR" stroke-width="3" stroke-linecap="round"/>
          <line x1="15" y1="15" x2="25" y2="15" stroke="FILL_COLOR" stroke-width="3" stroke-linecap="round"/>
          <line x1="15" y1="15" x2="15" y2="25" stroke="FILL_COLOR" stroke-width="3" stroke-linecap="round"/>
          <line x1="15" y1="15" x2="5" y2="15" stroke="FILL_COLOR" stroke-width="3" stroke-linecap="round"/>
          <circle cx="15" cy="15" r="6" fill="none" stroke="STROKE_COLOR" stroke-width="STROKE_WIDTH"/>
        `;

      case 'jet':
        // Jet icon - swept wings, pointed nose
        return `
          <path d="M15 1 L17 10 L28 13 L17 15 L17 25 L15 23 L13 25 L13 15 L2 13 L13 10 Z"
                fill="FILL_COLOR" stroke="STROKE_COLOR" stroke-width="STROKE_WIDTH"/>
        `;

      case 'prop':
        // Prop/GA icon - straight wings, rounded shape
        return `
          <path d="M15 3 L17 11 L27 13 L27 15 L17 17 L17 24 L15 22 L13 24 L13 17 L3 15 L3 13 L13 11 Z"
                fill="FILL_COLOR" stroke="STROKE_COLOR" stroke-width="STROKE_WIDTH"/>
        `;

      default:
        // Default aircraft icon
        return `
          <path d="M15 2 L18 12 L26 14 L18 16 L18 24 L15 22 L12 24 L12 16 L4 14 L12 12 Z"
                fill="FILL_COLOR" stroke="STROKE_COLOR" stroke-width="STROKE_WIDTH"/>
        `;
    }
  }

  scheduleListUpdate() {
    // Throttle list updates to avoid hover flashing
    if (this.listUpdateTimeout) return;
    this.listUpdateTimeout = setTimeout(() => {
      this.listUpdateTimeout = null;
      this.updateAircraftListUI();
    }, 500);
  }

  setupListHoverTracking() {
    const container = document.getElementById('aircraftList');
    if (container._hoverSetup) return;
    container._hoverSetup = true;

    container.addEventListener('mouseenter', (e) => {
      const item = e.target.closest('.aircraft-item');
      if (item) {
        this.hoveredIcao = item.dataset.icao;
      }
    }, true);

    container.addEventListener('mouseleave', (e) => {
      const item = e.target.closest('.aircraft-item');
      if (item && item.dataset.icao === this.hoveredIcao) {
        this.hoveredIcao = null;
      }
    }, true);
  }

  updateAircraftListUI() {
    const container = document.getElementById('aircraftList');
    this.setupListHoverTracking();

    const filtered = Object.values(this.aircraft)
      .filter(ac => this.passesFilter(ac))
      .sort((a, b) => this.sortAircraft(a, b));

    // Build new HTML
    const newHtml = filtered
      .map((ac) => this.renderAircraftItem(ac))
      .join('');

    // Only update if not hovering, or if it's been a while
    if (!this.hoveredIcao) {
      container.innerHTML = newHtml;
    } else {
      // Update only non-hovered items by replacing content carefully
      const tempDiv = document.createElement('div');
      tempDiv.innerHTML = newHtml;

      const existingItems = container.querySelectorAll('.aircraft-item');
      const newItems = tempDiv.querySelectorAll('.aircraft-item');

      // If counts differ significantly, do full update
      if (Math.abs(existingItems.length - newItems.length) > 2) {
        container.innerHTML = newHtml;
      }
    }
  }

  renderAircraftItem(ac) {
    const selected = this.selectedAircraft === ac.icao ? 'selected' : '';
    const hasPosition = ac.latitude != null ? 'has-position' : 'no-position';
    const signalBars = this.getSignalBars(ac.messages);
    const isPolice = this.isLawEnforcement(ac);
    const isMilitary = this.isMilitary(ac);

    let badge = '';
    let specialClass = '';
    if (isPolice) {
      badge = '<span class="police-badge-list" title="Law Enforcement">👮</span>';
      specialClass = 'law-enforcement';
    } else if (isMilitary) {
      badge = '<span class="military-badge-list" title="Military">🎖️</span>';
      specialClass = 'military';
    }

    const isTracked = this.isTracked(ac.icao);
    const trackedClass = isTracked ? 'tracked' : '';
    const trackedIcon = isTracked ? '<span class="tracked-icon" title="Tracked">📍</span>' : '';

    // Squawk display with emergency highlighting
    let squawkDisplay = '';
    if (ac.squawk) {
      let squawkClass = '';
      let squawkTitle = '';
      if (ac.squawk === '7700') {
        squawkClass = 'squawk-emergency';
        squawkTitle = 'EMERGENCY';
      } else if (ac.squawk === '7600') {
        squawkClass = 'squawk-radio';
        squawkTitle = 'Radio Failure';
      } else if (ac.squawk === '7500') {
        squawkClass = 'squawk-hijack';
        squawkTitle = 'HIJACK';
      } else if (ac.squawk === '1200') {
        squawkClass = 'squawk-vfr';
        squawkTitle = 'VFR';
      }
      squawkDisplay = `<span class="${squawkClass}" title="${squawkTitle || 'Squawk'}">🔢${ac.squawk}</span>`;
    }

    return `
      <div class="aircraft-item ${selected} ${hasPosition} ${specialClass} ${trackedClass}"
           data-icao="${ac.icao}"
           onmouseenter="tracker.hoveredIcao='${ac.icao}'"
           onmouseleave="tracker.hoveredIcao=null"
           onclick="tracker.selectAircraft('${ac.icao}')">
        <div class="aircraft-header">
          <div class="aircraft-callsign">${trackedIcon}${badge}${ac.callsign || 'Unknown'}</div>
          <div class="signal-indicator">${signalBars}</div>
        </div>
        <div class="aircraft-icao">${ac.icao}${squawkDisplay ? ' ' + squawkDisplay : ''}</div>
        <div class="aircraft-details">
          <span>${ac.altitude ? ac.altitude.toLocaleString() + ' ft' : '--'}</span>
          <span>${ac.speed ? ac.speed + ' kt' : '--'}</span>
          <span>${ac.heading ? ac.heading + '°' : '--'}</span>
        </div>
      </div>
    `;
  }

  getSignalBars(messages) {
    if (!messages) return '<span class="signal-bars weak"></span>';
    let strength = 'weak';
    if (messages > 50) strength = 'strong';
    else if (messages > 20) strength = 'medium';
    return `<span class="signal-bars ${strength}"></span>`;
  }

  selectAircraft(icao) {
    this.selectedAircraft = icao;
    const aircraft = this.aircraft[icao];

    if (aircraft) {
      // Clear registration info before fetching new data
      document.getElementById('infoRegistration').textContent = '--';
      document.getElementById('infoAircraftType').textContent = '';
      document.getElementById('infoOwner').textContent = '';

      // Clear route info
      const routeSection = document.getElementById('infoRouteSection');
      if (routeSection) routeSection.classList.add('hidden');

      this.updateInfoPanel(aircraft);
      document.getElementById('infoPanel').classList.remove('hidden');

      if (aircraft.latitude && aircraft.longitude) {
        this.map.setView([aircraft.latitude, aircraft.longitude], 10);
      }

      // Re-render to show selection highlight
      this.updateMarker(aircraft);

      // Fetch registration data from FAA database
      this.fetchAircraftInfo(icao);
    }

    this.updateAircraftListUI();
  }

  async fetchAircraftInfo(icao) {
    try {
      const response = await fetch(`/api/aircraft/${icao}`);
      if (response.ok) {
        const data = await response.json();
        if (data.registration && this.selectedAircraft === icao) {
          this.updateRegistrationInfo(data.registration);
        }
      }
    } catch (e) {
      // Ignore errors
    }

    // OpenSky flight route fetch disabled - API now requires authentication
    // this.fetchFlightInfo(icao);
  }

  async fetchFlightInfo(icao) {
    // Note: OpenSky historical flights API now requires authentication (403)
    // Keeping this code in case we add auth support later
    try {
      const response = await fetch(`/api/opensky/${icao}`);
      if (response.ok) {
        const data = await response.json();
        if (data.flight && this.selectedAircraft === icao) {
          this.updateFlightInfo(data.flight);
        }
      }
    } catch (e) {
      // OpenSky data not available
    }
  }

  updateFlightInfo(flight) {
    const routeEl = document.getElementById('infoRoute');
    const sectionEl = document.getElementById('infoRouteSection');
    if (!routeEl || !sectionEl) return;

    if (flight.origin && flight.destination) {
      routeEl.textContent = `${flight.origin} → ${flight.destination}`;
      sectionEl.classList.remove('hidden');
    } else if (flight.origin) {
      routeEl.textContent = `From: ${flight.origin}`;
      sectionEl.classList.remove('hidden');
    } else if (flight.destination) {
      routeEl.textContent = `To: ${flight.destination}`;
      sectionEl.classList.remove('hidden');
    } else {
      sectionEl.classList.add('hidden');
    }
  }

  updateRegistrationInfo(reg) {
    // Aircraft type (manufacturer + model)
    const typeEl = document.getElementById('infoAircraftType');
    if (reg.manufacturer && reg.model) {
      typeEl.textContent = `${reg.manufacturer.trim()} ${reg.model.trim()}`;
      if (reg.year) {
        typeEl.textContent += ` (${reg.year})`;
      }
    } else {
      typeEl.textContent = '';
    }

    // Registration N-number
    document.getElementById('infoRegistration').textContent = reg.n_number || '--';

    // Owner info
    const ownerEl = document.getElementById('infoOwner');
    if (reg.owner) {
      let ownerText = reg.owner.trim();
      if (reg.city && reg.state) {
        ownerText += ` - ${reg.city.trim()}, ${reg.state.trim()}`;
      }
      ownerEl.textContent = ownerText;
    } else {
      ownerEl.textContent = '';
    }
  }

  updateInfoPanel(aircraft) {
    document.getElementById('infoCallsign').textContent = aircraft.callsign || 'Unknown';
    document.getElementById('infoIcao').textContent = aircraft.icao;

    // Show/hide special type badges (law enforcement, military)
    const typeEl = document.getElementById('infoType');
    const isPolice = this.isLawEnforcement(aircraft);
    const isMilitary = this.isMilitary(aircraft);

    if (isPolice) {
      typeEl.innerHTML = '<span class="info-badge police">👮 Law Enforcement</span>';
      typeEl.classList.remove('hidden');
    } else if (isMilitary) {
      typeEl.innerHTML = '<span class="info-badge military">🎖️ Military</span>';
      typeEl.classList.remove('hidden');
    } else {
      typeEl.classList.add('hidden');
    }
    document.getElementById('infoAltitude').textContent = aircraft.altitude
      ? aircraft.altitude.toLocaleString() + ' ft'
      : '--';
    document.getElementById('infoSpeed').textContent = aircraft.speed
      ? aircraft.speed + ' kt'
      : '--';
    document.getElementById('infoHeading').textContent = aircraft.heading
      ? aircraft.heading + '°'
      : '--';

    // Vertical rate with arrow
    const vr = aircraft.vertical_rate;
    let vrText = '--';
    if (vr != null) {
      const arrow = vr > 100 ? ' ↑' : vr < -100 ? ' ↓' : '';
      vrText = vr + ' ft/min' + arrow;
    }
    document.getElementById('infoVerticalRate').textContent = vrText;

    document.getElementById('infoPosition').textContent =
      aircraft.latitude && aircraft.longitude
        ? `${aircraft.latitude.toFixed(4)}, ${aircraft.longitude.toFixed(4)}`
        : '--';

    // Distance from receiver
    const distanceEl = document.getElementById('infoDistance');
    if (aircraft.latitude && aircraft.longitude && this.receiverLocation) {
      const dist = this.calculateDistance(
        this.receiverLocation.lat, this.receiverLocation.lon,
        aircraft.latitude, aircraft.longitude
      );
      distanceEl.textContent = `${dist.toFixed(1)} nm`;
    } else {
      distanceEl.textContent = '--';
    }

    // Squawk code
    const squawkEl = document.getElementById('infoSquawk');
    if (aircraft.squawk) {
      squawkEl.textContent = aircraft.squawk;
      squawkEl.className = 'info-value';
      // Highlight emergency squawks
      if (['7500', '7600', '7700'].includes(aircraft.squawk)) {
        squawkEl.className = 'info-value squawk-emergency';
        squawkEl.textContent = aircraft.squawk + ' ' + this.getSquawkMeaning(aircraft.squawk);
      }
    } else {
      squawkEl.textContent = '--';
      squawkEl.className = 'info-value';
    }

    // Signal strength - values typically range 0.02-0.40
    // Display as percentage scaled to this range
    const signalEl = document.getElementById('infoSignal');
    if (aircraft.signal_strength) {
      // Scale: 0.02 = weak (~5%), 0.10 = medium (~25%), 0.40+ = strong (100%)
      const sigPct = Math.min(100, Math.round((aircraft.signal_strength / 0.4) * 100));
      signalEl.textContent = `${sigPct}%`;
      signalEl.className = 'info-value';
      if (sigPct > 50) signalEl.className = 'info-value signal-strong';
      else if (sigPct > 20) signalEl.className = 'info-value signal-medium';
      else signalEl.className = 'info-value signal-weak';
    } else {
      signalEl.textContent = '--';
      signalEl.className = 'info-value';
    }

    // Messages count
    document.getElementById('infoMessages').textContent = aircraft.messages || 0;

    // EHS (Enhanced Surveillance) data - only show if we have data
    // EHS comes from DF20/DF21 messages which require radar interrogation
    const ehsSection = document.getElementById('ehsSection');
    const hasEhsData = aircraft.selected_altitude || aircraft.roll_angle !== undefined ||
                       aircraft.magnetic_heading !== undefined || aircraft.indicated_airspeed ||
                       aircraft.mach || aircraft.baro_rate !== undefined;

    if (hasEhsData) {
      ehsSection.classList.remove('hidden');

      document.getElementById('infoSelAlt').textContent =
        aircraft.selected_altitude ? `${aircraft.selected_altitude.toLocaleString()} ft` : '--';

      document.getElementById('infoRoll').textContent =
        aircraft.roll_angle !== undefined ? `${aircraft.roll_angle}°` : '--';

      document.getElementById('infoMagHdg').textContent =
        aircraft.magnetic_heading !== undefined ? `${aircraft.magnetic_heading}°` : '--';

      document.getElementById('infoIAS').textContent =
        aircraft.indicated_airspeed ? `${aircraft.indicated_airspeed} kt` : '--';

      document.getElementById('infoMach').textContent =
        aircraft.mach ? aircraft.mach.toFixed(3) : '--';

      document.getElementById('infoBaroRate').textContent =
        aircraft.baro_rate !== undefined ? `${aircraft.baro_rate > 0 ? '+' : ''}${aircraft.baro_rate} fpm` : '--';
    } else {
      ehsSection.classList.add('hidden');
    }

    // Don't clear registration info here - it's filled by async fetch in selectAircraft

    // Update track button state
    const trackBtn = document.getElementById('trackBtn');
    if (trackBtn) {
      if (this.isTracked(aircraft.icao)) {
        trackBtn.textContent = '📍 Untrack';
        trackBtn.classList.add('tracking');
      } else {
        trackBtn.textContent = '📍 Track';
        trackBtn.classList.remove('tracking');
      }
    }
  }

  calculateDistance(lat1, lon1, lat2, lon2) {
    // Haversine formula - returns distance in nautical miles
    const R = 3440.065; // Earth radius in nautical miles
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon/2) * Math.sin(dLon/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
  }

  getSquawkMeaning(squawk) {
    switch (squawk) {
      case '7500': return '(HIJACK)';
      case '7600': return '(RADIO FAIL)';
      case '7700': return '(EMERGENCY)';
      default: return '';
    }
  }

  updateStatus(text, className) {
    const status = document.getElementById('status');
    status.textContent = text;
    status.className = `status ${className}`;
  }

  updateAircraftCount() {
    const filtered = Object.values(this.aircraft).filter(ac => this.passesFilter(ac));
    document.getElementById('aircraftCount').textContent = filtered.length;
  }

  updateMessageCount() {
    document.getElementById('messageCount').textContent = this.messageCount.toLocaleString();
  }

  // Filter methods
  setMinAltitude(value) {
    this.filters.minAltitude = parseInt(value) || 0;
    this.saveSettings();
    this.applyFilters();
  }

  setMaxAltitude(value) {
    this.filters.maxAltitude = parseInt(value) || 50000;
    this.saveSettings();
    this.applyFilters();
  }

  setSearchText(value) {
    this.filters.searchText = value;
    this.saveSettings();
    this.applyFilters();
  }

  setPositionOnly(value) {
    this.filters.positionOnly = value;
    this.saveSettings();
    this.applyFilters();
  }

  setSortBy(value) {
    this.filters.sortBy = value;
    this.saveSettings();
    this.updateAircraftListUI();
  }

  setOnlyMilitary(value) {
    this.filters.onlyMilitary = value;
    if (value) this.filters.onlyPolice = false; // Only one "only" filter at a time
    this.saveSettings();
    this.applyFilters();
    this.updateFilterUI();
  }

  setOnlyPolice(value) {
    this.filters.onlyPolice = value;
    if (value) this.filters.onlyMilitary = false; // Only one "only" filter at a time
    this.saveSettings();
    this.applyFilters();
    this.updateFilterUI();
  }

  setAircraftType(value) {
    this.filters.aircraftType = value;
    this.saveSettings();
    this.applyFilters();
  }

  updateFilterUI() {
    const milCheck = document.getElementById('filterOnlyMilitary');
    const polCheck = document.getElementById('filterOnlyPolice');
    if (milCheck) milCheck.checked = this.filters.onlyMilitary;
    if (polCheck) polCheck.checked = this.filters.onlyPolice;
  }

  sortAircraft(a, b) {
    switch (this.filters.sortBy) {
      case 'altitude':
        // Sort by altitude descending (highest first), nulls last
        const altA = a.altitude ?? -1;
        const altB = b.altitude ?? -1;
        return altB - altA;

      case 'distance':
        // Sort by distance ascending (closest first)
        const distA = this.getAircraftDistance(a);
        const distB = this.getAircraftDistance(b);
        return distA - distB;

      case 'signal':
        // Sort by message count descending (strongest first)
        return (b.messages || 0) - (a.messages || 0);

      case 'callsign':
      default:
        // Sort alphabetically by callsign/ICAO
        const nameA = a.callsign || a.icao;
        const nameB = b.callsign || b.icao;
        return nameA.localeCompare(nameB);
    }
  }

  getAircraftDistance(aircraft) {
    if (!aircraft.latitude || !aircraft.longitude || !this.receiverLocation) {
      return 99999;  // No position = sort to end
    }
    return this.calculateDistance(
      this.receiverLocation.lat, this.receiverLocation.lon,
      aircraft.latitude, aircraft.longitude
    );
  }

  applyFilters() {
    // Re-render all markers and list
    Object.values(this.aircraft).forEach(ac => this.updateMarker(ac));
    this.updateAircraftListUI();
    this.updateAircraftCount();
  }

  startStatsPolling() {
    this.fetchStats();
    this.statsInterval = setInterval(() => this.fetchStats(), 2000);
  }

  async fetchStats() {
    try {
      const response = await fetch('/api/stats');
      const stats = await response.json();
      if (!stats.error) {
        this.updateStats(stats);
      }
    } catch (e) {
      // Stats not available
    }
  }

  updateStats(stats) {
    if (stats.messages_total !== undefined) {
      this.messageCount = stats.messages_total;
      this.updateMessageCount();
    }

    if (stats.preambles_detected !== undefined) {
      document.getElementById('preambleCount').textContent = stats.preambles_detected.toLocaleString();
    }

    if (stats.crc_failures !== undefined) {
      document.getElementById('crcFailCount').textContent = stats.crc_failures.toLocaleString();
    }

    if (stats.frequency_mhz !== undefined) {
      document.getElementById('statFrequency').textContent = stats.frequency_mhz + ' MHz';
    }

    if (stats.sample_rate_mhz !== undefined) {
      document.getElementById('statSampleRate').textContent = stats.sample_rate_mhz + ' MHz';
    }

    if (stats.gain !== undefined) {
      document.getElementById('statGain').textContent = stats.gain + ' dB';
    }

    if (stats.uptime_seconds !== undefined) {
      document.getElementById('statUptime').textContent = this.formatUptime(stats.uptime_seconds);
    }
  }

  formatUptime(seconds) {
    if (seconds < 60) return seconds + 's';
    if (seconds < 3600) return Math.floor(seconds / 60) + 'm ' + (seconds % 60) + 's';
    const hours = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    return hours + 'h ' + mins + 'm';
  }

  // History stats polling
  startHistoryStatsPolling() {
    this.fetchHistoryStats();
    this.historyStatsInterval = setInterval(() => this.fetchHistoryStats(), 30000); // Every 30 seconds
  }

  async fetchHistoryStats() {
    try {
      const response = await fetch('/api/history/stats');
      const stats = await response.json();
      if (!stats.error) {
        this.updateHistoryStats(stats);
      }
    } catch (e) {
      // History stats not available
    }
  }

  updateHistoryStats(stats) {
    const el = (id) => document.getElementById(id);

    if (stats.aircraft_today !== undefined) {
      el('histAircraftToday').textContent = stats.aircraft_today.toLocaleString();
    }
    if (stats.total_aircraft_seen !== undefined) {
      el('histTotalAircraft').textContent = stats.total_aircraft_seen.toLocaleString();
    }
    if (stats.sightings_today !== undefined) {
      el('histSightingsToday').textContent = stats.sightings_today.toLocaleString();
    }
    if (stats.sightings_total !== undefined) {
      el('histTotalSightings').textContent = stats.sightings_total.toLocaleString();
    }

    // Most seen aircraft
    const mostSeenEl = el('histMostSeen');
    if (stats.most_seen_aircraft && mostSeenEl) {
      mostSeenEl.innerHTML = stats.most_seen_aircraft.slice(0, 5).map(ac =>
        `<div class="most-seen-item">
          <span class="most-seen-callsign">${escapeHtml(ac.callsign || ac.icao)}</span>
          <span class="most-seen-count">${parseInt(ac.count, 10) || 0} sightings</span>
        </div>`
      ).join('');
    }

    // Busiest hours
    const busiestEl = el('histBusiestHours');
    if (stats.busiest_hours && busiestEl) {
      busiestEl.innerHTML = stats.busiest_hours.slice(0, 5).map(h =>
        `<div class="busiest-hour-item">
          <span class="busiest-hour">${parseInt(h.hour, 10) || 0}:00</span>
          <span class="busiest-count">${(parseInt(h.count, 10) || 0).toLocaleString()}</span>
        </div>`
      ).join('');
    }
  }

  // Feed status polling
  startFeedStatusPolling() {
    this.fetchFeedStatus();
    this.feedStatusInterval = setInterval(() => this.fetchFeedStatus(), 10000); // Every 10 seconds
  }

  async fetchFeedStatus() {
    try {
      const response = await fetch('/api/feed/status');
      const status = await response.json();
      this.feedStatus = status;
      this.updateFeedStatusIndicator(status);
    } catch (e) {
      this.updateFeedStatusIndicator(null);
    }
  }

  updateFeedStatusIndicator(status) {
    const dot = document.querySelector('.feed-dot');
    const container = document.getElementById('feedStatus');
    if (!dot || !container) return;

    if (!status || !status.local?.running) {
      dot.className = 'feed-dot error';
      container.title = 'Feed offline';
      return;
    }

    const { aircraft_count, messages_total, uptime_seconds } = status.local;

    // Determine status based on activity
    if (aircraft_count > 0 && messages_total > 0) {
      dot.className = 'feed-dot active';
      container.title = `Feed active: ${aircraft_count} aircraft, ${messages_total.toLocaleString()} msgs`;
    } else if (uptime_seconds < 60) {
      dot.className = 'feed-dot warning';
      container.title = 'Feed starting up...';
    } else {
      dot.className = 'feed-dot warning';
      container.title = 'Feed active but no aircraft';
    }
  }

  showFeedStatus() {
    // Remove existing modal if any
    const existing = document.getElementById('feedModal');
    if (existing) {
      existing.remove();
      document.querySelector('.feed-overlay')?.remove();
      return;
    }

    const status = this.feedStatus;
    if (!status) {
      this.showNotification('Feed status unavailable');
      return;
    }

    const uptime = status.local?.uptime_seconds || 0;
    const uptimeStr = this.formatUptime(uptime);

    const overlay = document.createElement('div');
    overlay.className = 'feed-overlay';
    overlay.onclick = () => this.closeFeedModal();

    const modal = document.createElement('div');
    modal.id = 'feedModal';
    modal.className = 'feed-modal';
    modal.innerHTML = `
      <button class="feed-modal-close" onclick="tracker.closeFeedModal()">&times;</button>
      <h3>📡 Feed Status</h3>
      <div class="feed-stat">
        <span class="feed-stat-label">Status</span>
        <span class="feed-stat-value ${status.local?.running ? 'good' : ''}">${status.local?.running ? 'Running' : 'Offline'}</span>
      </div>
      <div class="feed-stat">
        <span class="feed-stat-label">Aircraft</span>
        <span class="feed-stat-value">${status.local?.aircraft_count || 0}</span>
      </div>
      <div class="feed-stat">
        <span class="feed-stat-label">Messages</span>
        <span class="feed-stat-value">${(status.local?.messages_total || 0).toLocaleString()}</span>
      </div>
      <div class="feed-stat">
        <span class="feed-stat-label">Uptime</span>
        <span class="feed-stat-value">${uptimeStr}</span>
      </div>
      <div class="feed-stat">
        <span class="feed-stat-label">Beast Feed</span>
        <span class="feed-stat-value">${status.feeds?.beast_endpoint || '--'}</span>
      </div>
      <div class="feed-stat">
        <span class="feed-stat-label">SBS Feed</span>
        <span class="feed-stat-value">${status.feeds?.sbs_endpoint || '--'}</span>
      </div>
    `;

    document.body.appendChild(overlay);
    document.body.appendChild(modal);
  }

  closeFeedModal() {
    document.getElementById('feedModal')?.remove();
    document.querySelector('.feed-overlay')?.remove();
  }

  // Settings modal
  showSettings() {
    // Remove existing modal if any
    const existing = document.getElementById('settingsModal');
    if (existing) {
      this.closeSettings();
      return;
    }

    const overlay = document.createElement('div');
    overlay.className = 'feed-overlay';
    overlay.onclick = () => this.closeSettings();

    const modal = document.createElement('div');
    modal.id = 'settingsModal';
    modal.className = 'settings-modal';
    modal.innerHTML = `
      <button class="settings-modal-close" onclick="tracker.closeSettings()">&times;</button>
      <h3>⚙️ Settings</h3>

      <div class="settings-section">
        <div class="settings-section-title">Display</div>
        <div class="settings-row">
          <span class="settings-label">Aircraft Trails</span>
          <div class="settings-toggle ${this.showTrails ? 'active' : ''}" onclick="tracker.toggleSettingTrails(this)"></div>
        </div>
        <div class="settings-row">
          <span class="settings-label">Aircraft Labels</span>
          <div class="settings-toggle ${this.showLabels ? 'active' : ''}" onclick="tracker.toggleSettingLabels(this)"></div>
        </div>
        <div class="settings-row">
          <span class="settings-label">Range Rings</span>
          <div class="settings-toggle ${this.showRangeRings ? 'active' : ''}" onclick="tracker.toggleSettingRangeRings(this)"></div>
        </div>
      </div>

      <div class="settings-section">
        <div class="settings-section-title">Alerts</div>
        <div class="settings-row">
          <span class="settings-label">Sound Alerts</span>
          <div class="settings-toggle ${this.soundEnabled ? 'active' : ''}" onclick="tracker.toggleSettingSound(this)"></div>
        </div>
        <div class="settings-row">
          <span class="settings-label">Push Notifications</span>
          <div class="settings-toggle ${this.notificationsEnabled ? 'active' : ''}" onclick="tracker.toggleSettingNotifications(this)"></div>
        </div>
        <div class="settings-row">
          <span class="settings-label">Military Aircraft</span>
          <div class="settings-toggle ${this.alertOnMilitary ? 'active' : ''}" onclick="tracker.toggleSettingMilitary(this)"></div>
        </div>
        <div class="settings-row">
          <span class="settings-label">Law Enforcement</span>
          <div class="settings-toggle ${this.alertOnPolice ? 'active' : ''}" onclick="tracker.toggleSettingPolice(this)"></div>
        </div>
        <div class="settings-row">
          <span class="settings-label">Emergency Squawks</span>
          <div class="settings-toggle ${this.alertOnEmergency ? 'active' : ''}" onclick="tracker.toggleSettingEmergency(this)"></div>
        </div>
      </div>

      <div class="settings-shortcuts">
        Keyboard: T=Trails L=Labels R=Rings S=Sound N=Notify M=Military P=Police
      </div>
    `;

    document.body.appendChild(overlay);
    document.body.appendChild(modal);
  }

  closeSettings() {
    document.getElementById('settingsModal')?.remove();
    document.querySelector('.feed-overlay')?.remove();
  }

  // Coverage analysis modal
  async showCoverage() {
    // Remove existing modal if any
    const existing = document.getElementById('coverageModal');
    if (existing) {
      this.closeCoverage();
      return;
    }

    if (!this.receiverLocation) {
      this.showNotification('Receiver location not set');
      return;
    }

    const overlay = document.createElement('div');
    overlay.className = 'feed-overlay';
    overlay.onclick = () => this.closeCoverage();

    const modal = document.createElement('div');
    modal.id = 'coverageModal';
    modal.className = 'coverage-modal';
    modal.innerHTML = `
      <button class="coverage-modal-close" onclick="tracker.closeCoverage()">&times;</button>
      <h3>📊 Coverage Analysis</h3>
      <div class="coverage-loading">Loading coverage data...</div>
    `;

    document.body.appendChild(overlay);
    document.body.appendChild(modal);

    // Fetch coverage data
    try {
      const response = await fetch(`/api/coverage?lat=${this.receiverLocation.lat}&lon=${this.receiverLocation.lon}&hours=168`);
      const data = await response.json();

      if (data.error) {
        modal.querySelector('.coverage-loading').textContent = data.error;
        return;
      }

      if (data.total_positions === 0) {
        modal.querySelector('.coverage-loading').textContent = 'No coverage data yet - need flight history';
        return;
      }

      this.renderCoverageModal(modal, data);
    } catch (e) {
      console.error('Failed to load coverage:', e);
      modal.querySelector('.coverage-loading').textContent = 'Failed to load coverage data';
    }
  }

  renderCoverageModal(modal, data) {
    modal.innerHTML = `
      <button class="coverage-modal-close" onclick="tracker.closeCoverage()">&times;</button>
      <h3>📊 Coverage Analysis</h3>
      <div class="coverage-subtitle">Last 7 days · ${data.total_positions.toLocaleString()} positions</div>

      <div class="coverage-stats">
        <div class="coverage-stat">
          <span class="coverage-stat-value">${data.max_range_nm}</span>
          <span class="coverage-stat-label">Max Range (nm)</span>
        </div>
        <div class="coverage-stat">
          <span class="coverage-stat-value">${data.avg_range_nm}</span>
          <span class="coverage-stat-label">Avg Range (nm)</span>
        </div>
      </div>

      <div class="coverage-section">
        <div class="coverage-section-title">Range by Direction</div>
        <div class="polar-chart-container">
          <canvas id="polarChart" width="220" height="220"></canvas>
        </div>
        <div class="direction-legend">
          ${data.range_by_bearing.map(d => `<span>${d.direction}: ${d.max_range}nm</span>`).join('')}
        </div>
      </div>

      <div class="coverage-section">
        <div class="coverage-section-title">Range by Altitude</div>
        <div class="altitude-bars">
          ${data.range_by_altitude.map(band => `
            <div class="altitude-bar-row">
              <span class="altitude-bar-label">${band.band}</span>
              <div class="altitude-bar-container">
                <div class="altitude-bar" style="width: ${Math.min(100, (band.max_range / data.max_range_nm) * 100)}%"></div>
              </div>
              <span class="altitude-bar-value">${band.max_range}nm</span>
            </div>
          `).join('')}
        </div>
      </div>

      <div class="coverage-section">
        <div class="coverage-section-title">Range Records</div>
        <div class="range-records">
          ${data.range_records.slice(0, 5).map((r, i) => `
            <div class="range-record">
              <span class="range-record-rank">#${i + 1}</span>
              <span class="range-record-dist">${r.distance_nm}nm</span>
              <span class="range-record-bearing">${this.bearingToDirection(r.bearing)}</span>
              <span class="range-record-alt">${r.altitude ? r.altitude.toLocaleString() + 'ft' : '--'}</span>
            </div>
          `).join('')}
        </div>
      </div>
    `;

    // Draw polar chart
    this.drawPolarChart(data.range_by_bearing, data.max_range_nm);
  }

  drawPolarChart(bearingData, maxRange) {
    const canvas = document.getElementById('polarChart');
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    const centerX = canvas.width / 2;
    const centerY = canvas.height / 2;
    const radius = Math.min(centerX, centerY) - 20;

    // Clear canvas
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Draw concentric circles (range rings)
    ctx.strokeStyle = '#2a4a7a';
    ctx.lineWidth = 1;
    for (let i = 1; i <= 4; i++) {
      ctx.beginPath();
      ctx.arc(centerX, centerY, (radius * i) / 4, 0, 2 * Math.PI);
      ctx.stroke();
    }

    // Draw direction lines
    for (let i = 0; i < 8; i++) {
      const angle = (i * 45 - 90) * Math.PI / 180;
      ctx.beginPath();
      ctx.moveTo(centerX, centerY);
      ctx.lineTo(centerX + radius * Math.cos(angle), centerY + radius * Math.sin(angle));
      ctx.stroke();
    }

    // Draw direction labels
    ctx.fillStyle = '#8892b0';
    ctx.font = '10px monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    labels.forEach((label, i) => {
      const angle = (i * 45 - 90) * Math.PI / 180;
      const labelRadius = radius + 12;
      ctx.fillText(label, centerX + labelRadius * Math.cos(angle), centerY + labelRadius * Math.sin(angle));
    });

    // Draw coverage polygon
    ctx.fillStyle = 'rgba(0, 191, 99, 0.3)';
    ctx.strokeStyle = '#00bf63';
    ctx.lineWidth = 2;
    ctx.beginPath();

    bearingData.forEach((d, i) => {
      const angle = (i * 45 - 90) * Math.PI / 180;
      const r = maxRange > 0 ? (d.max_range / maxRange) * radius : 0;
      const x = centerX + r * Math.cos(angle);
      const y = centerY + r * Math.sin(angle);
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    });

    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Draw center point
    ctx.fillStyle = '#ff6b6b';
    ctx.beginPath();
    ctx.arc(centerX, centerY, 4, 0, 2 * Math.PI);
    ctx.fill();
  }

  bearingToDirection(bearing) {
    const directions = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    const index = Math.round(bearing / 22.5) % 16;
    return directions[index];
  }

  closeCoverage() {
    document.getElementById('coverageModal')?.remove();
    document.querySelector('.feed-overlay')?.remove();
  }

  toggleSettingTrails(el) {
    this.toggleTrails();
    el.classList.toggle('active', this.showTrails);
  }

  toggleSettingLabels(el) {
    this.toggleLabels();
    el.classList.toggle('active', this.showLabels);
  }

  toggleSettingRangeRings(el) {
    this.toggleRangeRings();
    el.classList.toggle('active', this.showRangeRings);
  }

  toggleSettingSound(el) {
    this.toggleSound();
    el.classList.toggle('active', this.soundEnabled);
  }

  async toggleSettingNotifications(el) {
    await this.toggleNotifications();
    el.classList.toggle('active', this.notificationsEnabled);
  }

  toggleSettingMilitary(el) {
    this.toggleMilitaryAlerts();
    el.classList.toggle('active', this.alertOnMilitary);
  }

  toggleSettingPolice(el) {
    this.togglePoliceAlerts();
    el.classList.toggle('active', this.alertOnPolice);
  }

  toggleSettingEmergency(el) {
    this.toggleEmergencyAlerts();
    el.classList.toggle('active', this.alertOnEmergency);
  }

  // Heatmap toggle
  async toggleHeatmap() {
    if (!this.showHeatmap) {
      // Turning on - try to load data
      const success = await this.loadHeatmap();
      if (success) {
        this.showHeatmap = true;
        this.showNotification('Heatmap ON');
      }
    } else {
      // Turning off
      this.clearHeatmap();
      this.showHeatmap = false;
      this.showNotification('Heatmap OFF');
    }
  }

  async loadHeatmap() {
    try {
      const response = await fetch('/api/history/heatmap?hours=24&limit=5000');
      const data = await response.json();

      if (data.error) {
        this.showNotification('Heatmap unavailable - restart server');
        return false;
      }

      if (data.positions && data.positions.length > 0) {
        this.heatmapData = data.positions;
        this.renderHeatmap();
        return true;
      } else {
        this.showNotification('No heatmap data yet - need flight history');
        return false;
      }
    } catch (e) {
      console.error('Failed to load heatmap:', e);
      this.showNotification('Heatmap failed to load');
      return false;
    }
  }

  renderHeatmap() {
    this.clearHeatmap();

    // Create circle markers for each position with count-based opacity
    const maxCount = Math.max(...this.heatmapData.map(p => p.count));

    this.heatmapLayer = L.layerGroup();

    this.heatmapData.forEach(pos => {
      const opacity = 0.1 + (pos.count / maxCount) * 0.7;
      const radius = 2000 + (pos.count / maxCount) * 8000;

      const circle = L.circle([pos.lat, pos.lon], {
        radius: radius,
        color: '#e94560',
        fillColor: '#e94560',
        fillOpacity: opacity * 0.5,
        weight: 0
      });

      this.heatmapLayer.addLayer(circle);
    });

    this.heatmapLayer.addTo(this.map);
  }

  clearHeatmap() {
    if (this.heatmapLayer) {
      this.map.removeLayer(this.heatmapLayer);
      this.heatmapLayer = null;
    }
  }

  // Notification initialization
  initNotifications() {
    if ('Notification' in window) {
      this.notificationPermission = Notification.permission;
      if (this.notificationsEnabled && this.notificationPermission === 'granted') {
        console.log('Push notifications enabled');
      }
    }
  }

  async requestNotificationPermission() {
    if (!('Notification' in window)) {
      this.showNotification('Notifications not supported in this browser');
      return false;
    }

    if (Notification.permission === 'granted') {
      return true;
    }

    if (Notification.permission !== 'denied') {
      const permission = await Notification.requestPermission();
      this.notificationPermission = permission;
      return permission === 'granted';
    }

    this.showNotification('Notifications blocked - check browser settings');
    return false;
  }

  async toggleNotifications() {
    if (!this.notificationsEnabled) {
      const granted = await this.requestNotificationPermission();
      if (granted) {
        this.notificationsEnabled = true;
        this.saveSettings();
        this.showNotification('Push notifications ON');
        // Test notification
        this.sendPushNotification('ADS-B Tracker', 'Notifications enabled!', 'info');
      }
    } else {
      this.notificationsEnabled = false;
      this.saveSettings();
      this.showNotification('Push notifications OFF');
    }
  }

  sendPushNotification(title, body, type = 'info') {
    if (!this.notificationsEnabled || Notification.permission !== 'granted') {
      return;
    }

    const icon = type === 'emergency' ? '🚨' : type === 'military' ? '🎖️' : '✈️';

    const notification = new Notification(title, {
      body: body,
      icon: `/favicon.ico`,
      badge: `/favicon.ico`,
      tag: `adsb-${type}-${Date.now()}`,
      requireInteraction: type === 'emergency',
      silent: false
    });

    notification.onclick = () => {
      window.focus();
      notification.close();
    };

    // Auto-close non-emergency notifications
    if (type !== 'emergency') {
      setTimeout(() => notification.close(), 10000);
    }
  }

  // Sound alerts
  toggleSound() {
    this.soundEnabled = !this.soundEnabled;
    this.saveSettings();
    this.showNotification(`Sound alerts ${this.soundEnabled ? 'ON' : 'OFF'}`);

    // Test sound on enable
    if (this.soundEnabled) {
      this.playSound('click');
    }
  }

  checkAlerts(aircraft) {
    const alertsEnabled = this.soundEnabled || this.notificationsEnabled;
    if (!alertsEnabled) return;

    const now = Date.now();
    if (now - this.lastAlertTime < 3000) return; // Rate limit

    // Check for emergency squawks
    if (this.alertOnEmergency && aircraft.squawk && ['7500', '7600', '7700'].includes(aircraft.squawk)) {
      const alertKey = `${aircraft.icao}-${aircraft.squawk}`;
      if (!this.alertedEmergencies.has(alertKey)) {
        this.alertedEmergencies.add(alertKey);
        const squawkMeaning = this.getSquawkMeaning(aircraft.squawk);
        const message = `${aircraft.callsign || aircraft.icao} squawking ${aircraft.squawk} ${squawkMeaning}`;

        if (this.soundEnabled) {
          this.playSound('emergency');
        }
        this.showNotification(`⚠️ EMERGENCY: ${message}`);
        this.sendPushNotification('🚨 EMERGENCY SQUAWK', message, 'emergency');
        this.lastAlertTime = now;
      }
    }

    // Check for military aircraft
    if (this.alertOnMilitary && this.isMilitary(aircraft)) {
      const alertKey = `military-${aircraft.icao}`;
      if (!this.alertedEmergencies.has(alertKey)) {
        this.alertedEmergencies.add(alertKey);
        const message = `${aircraft.callsign || aircraft.icao}`;

        if (this.soundEnabled) {
          this.playSound('military');
        }
        this.showNotification(`🎖️ Military aircraft: ${message}`);
        this.sendPushNotification('Military Aircraft Detected', message, 'military');
        this.lastAlertTime = now;

        // Clear after 10 minutes so it can alert again if it leaves and comes back
        setTimeout(() => this.alertedEmergencies.delete(alertKey), 600000);
      }
    }

    // Check for law enforcement aircraft
    if (this.alertOnPolice && this.isLawEnforcement(aircraft)) {
      const alertKey = `police-${aircraft.icao}`;
      if (!this.alertedEmergencies.has(alertKey)) {
        this.alertedEmergencies.add(alertKey);
        const message = `${aircraft.callsign || aircraft.icao}`;

        if (this.soundEnabled) {
          this.playSound('police');
        }
        this.showNotification(`👮 Law enforcement: ${message}`);
        this.sendPushNotification('Law Enforcement Aircraft', message, 'police');
        this.lastAlertTime = now;

        // Clear after 10 minutes
        setTimeout(() => this.alertedEmergencies.delete(alertKey), 600000);
      }
    }

    // Check for tracked aircraft by ICAO
    if (this.trackedAircraft.has(aircraft.icao.toUpperCase())) {
      const alertKey = `track-${aircraft.icao}`;
      if (!this.alertedEmergencies.has(alertKey)) {
        this.alertedEmergencies.add(alertKey);
        const message = `${aircraft.callsign || aircraft.icao}`;

        if (this.soundEnabled) {
          this.playSound('tracked');
        }
        this.showNotification(`📍 Tracked aircraft: ${message}`);
        this.sendPushNotification('Tracked Aircraft', message, 'tracked');
        this.lastAlertTime = now;

        // Clear after 5 minutes so it can alert again
        setTimeout(() => this.alertedEmergencies.delete(alertKey), 300000);
      }
    }

    // Check for tracked callsigns
    const callsign = (aircraft.callsign || '').toUpperCase().trim();
    if (callsign && this.trackedCallsigns.has(callsign)) {
      const alertKey = `track-callsign-${callsign}`;
      if (!this.alertedEmergencies.has(alertKey)) {
        this.alertedEmergencies.add(alertKey);
        const message = `${callsign} (${aircraft.icao})`;

        if (this.soundEnabled) {
          this.playSound('tracked');
        }
        this.showNotification(`📍 Tracked callsign: ${message}`);
        this.sendPushNotification('Tracked Callsign', message, 'tracked');
        this.lastAlertTime = now;

        // Clear after 5 minutes so it can alert again
        setTimeout(() => this.alertedEmergencies.delete(alertKey), 300000);
      }
    }
  }

  playSound(type) {
    const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const oscillator = audioCtx.createOscillator();
    const gainNode = audioCtx.createGain();

    oscillator.connect(gainNode);
    gainNode.connect(audioCtx.destination);

    switch (type) {
      case 'emergency':
        // Urgent alarm - high pitch alternating
        oscillator.frequency.setValueAtTime(880, audioCtx.currentTime);
        oscillator.frequency.setValueAtTime(660, audioCtx.currentTime + 0.15);
        oscillator.frequency.setValueAtTime(880, audioCtx.currentTime + 0.3);
        oscillator.frequency.setValueAtTime(660, audioCtx.currentTime + 0.45);
        gainNode.gain.setValueAtTime(0.3, audioCtx.currentTime);
        oscillator.start();
        oscillator.stop(audioCtx.currentTime + 0.6);
        break;

      case 'military':
        // Military alert - authoritative triple beep
        oscillator.frequency.setValueAtTime(587, audioCtx.currentTime); // D5
        oscillator.frequency.setValueAtTime(440, audioCtx.currentTime + 0.1); // A4
        oscillator.frequency.setValueAtTime(587, audioCtx.currentTime + 0.2); // D5
        gainNode.gain.setValueAtTime(0.25, audioCtx.currentTime);
        oscillator.start();
        oscillator.stop(audioCtx.currentTime + 0.3);
        break;

      case 'police':
        // Police alert - two-tone siren style
        oscillator.frequency.setValueAtTime(392, audioCtx.currentTime); // G4
        oscillator.frequency.setValueAtTime(494, audioCtx.currentTime + 0.15); // B4
        oscillator.frequency.setValueAtTime(392, audioCtx.currentTime + 0.3); // G4
        gainNode.gain.setValueAtTime(0.25, audioCtx.currentTime);
        oscillator.start();
        oscillator.stop(audioCtx.currentTime + 0.4);
        break;

      case 'tracked':
        // Pleasant double beep
        oscillator.frequency.setValueAtTime(523, audioCtx.currentTime);
        oscillator.frequency.setValueAtTime(659, audioCtx.currentTime + 0.1);
        gainNode.gain.setValueAtTime(0.2, audioCtx.currentTime);
        oscillator.start();
        oscillator.stop(audioCtx.currentTime + 0.2);
        break;

      case 'click':
      default:
        // Simple click
        oscillator.frequency.setValueAtTime(440, audioCtx.currentTime);
        gainNode.gain.setValueAtTime(0.1, audioCtx.currentTime);
        oscillator.start();
        oscillator.stop(audioCtx.currentTime + 0.05);
    }
  }

  trackAircraft(icao) {
    const upperIcao = icao.toUpperCase();
    if (this.trackedAircraft.has(upperIcao)) {
      this.trackedAircraft.delete(upperIcao);
      this.showNotification(`Untracked: ${icao}`);
    } else {
      this.trackedAircraft.add(upperIcao);
      this.showNotification(`Now tracking: ${icao}`);
    }
    this.saveSettings();
    this.updateAircraftListUI();
  }

  trackCallsign(callsign) {
    const upperCallsign = callsign.toUpperCase().trim();
    if (!upperCallsign) return;

    if (this.trackedCallsigns.has(upperCallsign)) {
      this.trackedCallsigns.delete(upperCallsign);
      this.showNotification(`Untracked callsign: ${callsign}`);
    } else {
      this.trackedCallsigns.add(upperCallsign);
      this.showNotification(`Now tracking callsign: ${callsign}`);
    }
    this.saveSettings();
    this.updateAircraftListUI();
  }

  isTracked(icao) {
    return this.trackedAircraft.has(icao.toUpperCase());
  }

  isCallsignTracked(callsign) {
    return this.trackedCallsigns.has((callsign || '').toUpperCase().trim());
  }

  toggleMilitaryAlerts() {
    this.alertOnMilitary = !this.alertOnMilitary;
    this.saveSettings();
    this.showNotification(`Military alerts ${this.alertOnMilitary ? 'ON' : 'OFF'}`);
  }

  togglePoliceAlerts() {
    this.alertOnPolice = !this.alertOnPolice;
    this.saveSettings();
    this.showNotification(`Police alerts ${this.alertOnPolice ? 'ON' : 'OFF'}`);
  }

  toggleEmergencyAlerts() {
    this.alertOnEmergency = !this.alertOnEmergency;
    this.saveSettings();
    this.showNotification(`Emergency alerts ${this.alertOnEmergency ? 'ON' : 'OFF'}`);
  }

  getTrackedCallsigns() {
    return Array.from(this.trackedCallsigns);
  }

  getTrackedAircraft() {
    return Array.from(this.trackedAircraft);
  }

  // CSV Export
  async exportCSV() {
    try {
      const response = await fetch('/api/export/csv');
      if (!response.ok) throw new Error('Export failed');

      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `adsb-export-${new Date().toISOString().slice(0,10)}.csv`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);

      this.showNotification('CSV exported successfully');
    } catch (e) {
      this.showNotification('Export failed: ' + e.message);
    }
  }

  // Export current aircraft to CSV
  exportCurrentAircraft() {
    const aircraft = Object.values(this.aircraft);
    if (aircraft.length === 0) {
      this.showNotification('No aircraft to export');
      return;
    }

    const headers = ['ICAO', 'Callsign', 'Latitude', 'Longitude', 'Altitude', 'Speed', 'Heading', 'Squawk', 'Messages'];
    const rows = aircraft.map(ac => [
      ac.icao,
      ac.callsign || '',
      ac.latitude || '',
      ac.longitude || '',
      ac.altitude || '',
      ac.speed || '',
      ac.heading || '',
      ac.squawk || '',
      ac.messages || 0
    ]);

    const csv = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `aircraft-${new Date().toISOString().slice(0,19).replace(/:/g, '-')}.csv`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    this.showNotification(`Exported ${aircraft.length} aircraft`);
  }
}

function closeInfoPanel() {
  document.getElementById('infoPanel').classList.add('hidden');
  if (window.tracker) {
    window.tracker.selectedAircraft = null;
    window.tracker.updateAircraftListUI();
  }
}

// Initialize tracker
const tracker = new ADSBTracker();
window.tracker = tracker;
