//
//  ViewController.swift
//  GPSLogger
//
//  Created by koogawa on 2018/12/02.
//  Copyright (c) 2018 Kosuke Ogawa. All rights reserved.
//

import UIKit
import MapKit
import FirebaseFirestore

struct Location {
    let latitude: Double
    let longitude: Double
    let createdAt: Date

    init(latitude: Double, longitude: Double, createdAt: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }

    init(document: [String: Any]) {
        latitude = document["latitude"] as? Double ?? 0
        longitude = document["longitude"] as? Double ?? 0
        createdAt = document["createdAt"] as? Date ?? Date()
    }
}

class ViewController: UIViewController {

    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var tableView: UITableView!

    let kLocationsCollectionName = "locations"

    var locationManager: CLLocationManager!
    var listener: ListenerRegistration!
    var isUpdating = false

    var locations: [Location] = [] {
        didSet {
            tableView.reloadData()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view, typically from a nib.
        self.locationManager = CLLocationManager()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.distanceFilter = 100

        // Delete old location objects
        self.deleteOldLocations()

        // Load stored location objects
        self.loadStoredLocations()

        // Drop pins
        for location in self.locations {
            self.dropPin(at: location)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


    // MARK: - Private methods

    @IBAction func startButtonDidTap(_ sender: AnyObject) {
        self.toggleLocationUpdate()
    }

    @IBAction func clearButtonDidTap(_ sender: AnyObject) {
        self.deleteAllLocations()
        self.removeAllAnnotations()
    }

    // Load stored locations on firebase
    fileprivate func loadStoredLocations() {
        let db = Firestore.firestore()
        db.collection(kLocationsCollectionName)
            .order(by: "createdAt", descending: false)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("Error getting documents: \(error)")
                } else {
                    self?.locations = snapshot?.documents.map { Location(document: $0.data()) } ?? []
                }
        }
    }

    // Start or Stop location update
    fileprivate func toggleLocationUpdate() {
        if self.isUpdating {
            // Stop
            self.isUpdating = false
            self.locationManager.stopUpdatingLocation()
            self.startButton.setTitle("Start", for: UIControl.State())

            // Remove Realtime Update
            self.listener.remove()
        } else {
            // Start
            self.isUpdating = true
            self.locationManager.startUpdatingLocation()
            self.startButton.setTitle("Stop", for: UIControl.State())

            // Cloud Firestore Realtime Update
            let db = Firestore.firestore()
            self.listener = db.collection(kLocationsCollectionName)
                .addSnapshotListener(includeMetadataChanges: true) { [weak self] documentSnapshot, error in
                    guard let document = documentSnapshot else {
                        print("Error fetching document: \(error!)")
                        return
                    }
                    print("Current data: \(document.description)")
                    self?.loadStoredLocations()
            }
        }
    }

    // Add a new document in collection "locations"
    fileprivate func add(location: CLLocation) {
        let db = Firestore.firestore()
        var ref: DocumentReference? = nil
        ref = db.collection(kLocationsCollectionName).addDocument(data: [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "createdAt": FieldValue.serverTimestamp()
        ]) { err in
            if let err = err {
                print("Error adding document: \(err)")
            } else {
                print("Document added with ID: \(ref!.documentID)")
            }
        }
    }

    // Delete old (-1 day) objects in a background thread
    fileprivate func deleteOldLocations() {
        /*
        DispatchQueue.global().async {
            // Get the default Realm
            let realm = try! Realm()

            // Old Locations stored in Realm
            let oldLocations = realm.objects(Location.self).filter(NSPredicate(format:"createdAt < %@", NSDate().addingTimeInterval(-86400)))

            // Delete an object with a transaction
            try! realm.write {
                realm.delete(oldLocations)
            }
        }
 */
    }

    // Delete all location objects from realm
    fileprivate func deleteAllLocations() {
        let db = Firestore.firestore()
        db.collection(kLocationsCollectionName)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error getting documents: \(error)")
                    return
                }
                for document in snapshot?.documents ?? [] {
                    print("Deleting document", document)
                    db.collection(self.kLocationsCollectionName)
                        .document(document.documentID)
                        .delete() { err in
                            if let err = err {
                                print("Error removing document: \(err)")
                            } else {
                                print("Document successfully removed!")
                            }
                    }
                }
        }
    }

    // Drop pin on the map
    fileprivate func dropPin(at location: Location) {
        let annotation = MKPointAnnotation()
        annotation.coordinate = CLLocationCoordinate2DMake(location.latitude, location.longitude)
        annotation.title = "\(location.latitude),\(location.longitude)"
        annotation.subtitle = location.createdAt.description
        self.mapView.addAnnotation(annotation)
    }

    // Remove all pins on the map
    fileprivate func removeAllAnnotations() {
        let annotations = self.mapView.annotations.filter {
            $0 !== self.mapView.userLocation
        }
        self.mapView.removeAnnotations(annotations)
    }
}

// MARK: - CLLocationManager delegate
extension ViewController: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == CLAuthorizationStatus.notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
        else if status == CLAuthorizationStatus.authorizedAlways || status == CLAuthorizationStatus.authorizedWhenInUse {
            // Center user location on the map
            let span = MKCoordinateSpan.init(latitudeDelta: 0.003, longitudeDelta: 0.003)
            let region = MKCoordinateRegion.init(center: self.mapView.userLocation.coordinate, span: span)
            self.mapView.setRegion(region, animated:true)
            self.mapView.userTrackingMode = MKUserTrackingMode.followWithHeading
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations:[CLLocation]) {
        guard let newLocation = locations.last else {
            return
        }

        if !CLLocationCoordinate2DIsValid(newLocation.coordinate) {
            return
        }

        self.add(location: newLocation)

        let location = Location(latitude: newLocation.coordinate.latitude,
                                longitude: newLocation.coordinate.longitude)
        self.dropPin(at: location)
    }
}

// MARK: - MKMapView delegate
extension ViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        }

        let reuseId = "annotationIdentifier"

        var pinView = self.mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) as? MKPinAnnotationView
        if pinView == nil {
            pinView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: reuseId)
            pinView?.canShowCallout = true
            pinView?.animatesDrop = true
        }
        else {
            pinView?.annotation = annotation
        }

        return pinView
    }
}

// MARK: - Table view data source
extension ViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        // Return the number of sections.
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Return the number of rows in the section.
        return self.locations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CellIdentifier", for: indexPath) 

        let location = self.locations[indexPath.row]
        cell.textLabel?.text = "\(location.latitude),\(location.longitude)"
        cell.detailTextLabel?.text = location.createdAt.description

        return cell
    }
}

// MARK: - Table view delegate
extension ViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
