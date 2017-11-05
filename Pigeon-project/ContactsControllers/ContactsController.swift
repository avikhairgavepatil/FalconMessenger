//
//  ContactsController.swift
//  Pigeon-project
//
//  Created by Roman Mizin on 8/2/17.
//  Copyright © 2017 Roman Mizin. All rights reserved.
//

import UIKit
import Contacts
import PhoneNumberKit
import Firebase
import SDWebImage


class ContactsController: UITableViewController {
  
  let phoneNumberKit = PhoneNumberKit()
  
  var contacts = [CNContact]()
  
  var filteredContacts = [CNContact]()
  
  var localPhones = [String]()
  
  var users = [User]()
  
  var filteredUsers = [User]()
  
  let contactsCellID = "contactsCellID"
  
  let pigeonUsersCellID = "pigeonUsersCellID"
  
  private let reloadAnimation = UITableViewRowAnimation.none
  
  var searchBar: UISearchBar?
    
  var searchContactsController: UISearchController?
  

    override func viewDidLoad() {
        super.viewDidLoad()
        
      view.backgroundColor = .white
      extendedLayoutIncludesOpaqueBars = true
      edgesForExtendedLayout = UIRectEdge.top
     
      setupTableView()
      fetchContacts()
      setupSearchController()
    }
    
    
    fileprivate func setupTableView() {
        
        tableView.register(ContactsTableViewCell.self, forCellReuseIdentifier: contactsCellID)
        tableView.register(PigeonUsersTableViewCell.self, forCellReuseIdentifier: pigeonUsersCellID)
        tableView.separatorStyle = .none
        tableView.prefetchDataSource = self
    }
    
    fileprivate func setupSearchController() {
        
        if #available(iOS 11.0, *) {
            
            searchContactsController = UISearchController(searchResultsController: nil)
            searchContactsController?.searchResultsUpdater = self
            searchContactsController?.obscuresBackgroundDuringPresentation = false
            definesPresentationContext = true
            searchContactsController?.searchBar.delegate = self
            navigationItem.searchController = searchContactsController
            
        } else {
            
            searchBar = UISearchBar()
            searchBar?.delegate = self
            searchBar?.searchBarStyle = .minimal
            searchBar?.frame = CGRect(x: 0, y: 0, width: view.frame.width, height: 50)
            tableView.tableHeaderView = searchBar
            tableView.contentOffset = CGPoint(x: 0.0, y: 44.0)
        }
    }
  

 fileprivate func fetchContacts () {
    
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .denied || status == .restricted {
      presentSettingsActionSheet()
      return
    }
    
    // open it
    let store = CNContactStore()
    store.requestAccess(for: .contacts) { granted, error in
      guard granted else {
        DispatchQueue.main.async {
          self.presentSettingsActionSheet()
        }
        return
      }
      
      // get the contacts
      let request = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as NSString, CNContactPhoneNumbersKey as NSString, CNContactFormatter.descriptorForRequiredKeys(for: .fullName)])
      do {
        try store.enumerateContacts(with: request) { contact, stop in
          self.contacts.append(contact)
        }
      } catch {
        print(error)
      }
      
      self.localPhones.removeAll()
      self.filteredContacts = self.contacts

      for contact in self.contacts {
       
        for phone in contact.phoneNumbers {
        
          self.localPhones.append(phone.value.stringValue)
        }
      }
      
      self.fetchPigeonUsers()
    }
  }
  
  
 fileprivate func rearrangeUsers() { /* Moves Online users to the top  */
    for index in 0...self.users.count - 1 {
      if self.users[index].onlineStatus == statusOnline {
        self.users = rearrange(array: self.users, fromIndex: index, toIndex: 0)
      }
    }
  }
  
 fileprivate func rearrangeFilteredUsers() { /* Moves Online users to the top  */
    for index in 0...self.filteredUsers.count - 1 {
      if self.filteredUsers[index].onlineStatus == statusOnline {
        self.filteredUsers = rearrange(array: self.filteredUsers, fromIndex: index, toIndex: 0)
      }
    }
  }
  
 fileprivate func sortUsers() { /* Sort users by las online date  */
    self.users.sort(by: { (user1, user2) -> Bool in
     return (user1.onlineStatus ?? "", user1.phoneNumber ?? "") > (user2.onlineStatus ?? "", user2.phoneNumber ?? "") // sort
    })
  }

  
 fileprivate func fetchPigeonUsers() {
  
    var preparedNumber = String()
    users.removeAll()
    
    for number in localPhones {
      
      do {
        let countryCode = try self.phoneNumberKit.parse(number).countryCode
        let nationalNumber = try self.phoneNumberKit.parse(number).nationalNumber
        preparedNumber = "+" + String(countryCode) + String(nationalNumber)
        
      
      } catch {
       // print("Generic parser error")
      }

      var userRef: DatabaseQuery = Database.database().reference().child("users")
      userRef = userRef.queryOrdered(byChild: "phoneNumber").queryEqual(toValue: preparedNumber )
      userRef.observeSingleEvent(of: .value, with: { (snapshot) in
      userRef.keepSynced(true)
        
        if snapshot.exists() {
         
          self.startObservingUserChanges(at: userRef)
         
          // Initial load
          for child in snapshot.children.allObjects as! [DataSnapshot]  {
  
            guard var dictionary = child.value as? [String: AnyObject] else {
              return
            }
            
            dictionary.updateValue(child.key as AnyObject, forKey: "id")
            
            self.users.append(User(dictionary: dictionary))
            
            self.sortUsers()
            
            self.rearrangeUsers()

            self.filteredUsers = self.users
            
            DispatchQueue.main.async {
              self.tableView.reloadData()
            }
          }
        }
        
      }, withCancel: { (error) in
        //search error
      })
    }
  }

 
  fileprivate func userStatusChangedDuringSearch(snap: DataSnapshot) {
    
    guard var dictionary = snap.value as? [String: AnyObject] else {
      return
    }
    
    dictionary.updateValue(snap.key as AnyObject, forKey: "id")
    
    for index in 0...self.filteredUsers.count - 1  {
      
      if self.filteredUsers[index].id == snap.key {
        
        self.filteredUsers[index] = User(dictionary: dictionary)
      
        rearrangeUsers()
        
        rearrangeFilteredUsers()

        self.tableView.beginUpdates()
        
        for indexOfIndexPath in 0...self.filteredUsers.count - 1 {
          self.tableView.reloadRows(at: [IndexPath(row: indexOfIndexPath, section: 0)], with: self.reloadAnimation)
        }
        
        self.tableView.endUpdates()
      }
    }
  }
  
  
 fileprivate func startObservingUserChanges(at userRef: DatabaseQuery) {
    
    // user updates observer
    userRef.observe(.childChanged, with: { (snap) in
      
      guard var dictionary = snap.value as? [String: AnyObject] else {
        return
      }
      
      dictionary.updateValue(snap.key as AnyObject, forKey: "id")
      
      for index in 0...self.users.count - 1 {
        
        if self.users[index].id == snap.key {
          
          self.users[index] = User(dictionary: dictionary)
          
          self.sortUsers()
          
          if self.users[index].onlineStatus == statusOnline {
            self.users = rearrange(array: self.users, fromIndex: index, toIndex: 0)
          }
            var searchBar: UISearchBar?
            
            if #available(iOS 11.0, *) {
                searchBar = self.searchContactsController?.searchBar
            
            } else {
                searchBar = self.searchBar
            }
            
          
            if searchBar?.text != "" && self.filteredUsers.count != 0 {
            
            self.userStatusChangedDuringSearch(snap: snap)
            
          } else if self.filteredUsers.count == 0 {
            
          } else {
            
            self.sortUsers()
            
            self.rearrangeUsers()
            
            self.filteredUsers = self.users
            
            self.tableView.beginUpdates()
            
            for indexOfIndexPath in 0...self.filteredUsers.count - 1 {
              self.tableView.reloadRows(at: [IndexPath(row: indexOfIndexPath, section: 0)], with: self.reloadAnimation)
            }
            
            self.tableView.endUpdates()
          }
        }
      }
    })
  }
  
  
 fileprivate func presentSettingsActionSheet() {
    let alert = UIAlertController(title: "Permission to Contacts", message: "This app needs access to contacts in order to ...", preferredStyle: .actionSheet)
    alert.addAction(UIAlertAction(title: "Go to Settings", style: .default) { _ in
      let url = URL(string: UIApplicationOpenSettingsURLString)!
      UIApplication.shared.open(url)
    })
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(alert, animated: true)
  }


    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
      
      if section == 0 {
        return filteredUsers.count
      } else {
         return filteredContacts.count
      }
    }
  
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
      return 65
    }
  
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
      if section == 0 {
      
        if filteredUsers.count == 0 {
          return ""
        } else {
          return "Pigeon contacts"
        }
      
      } else {
        return "All contacts"
      }
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
      view.tintColor = .white
    }
  
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    
     return selectCell(for: indexPath)!
    }
  
  
  func selectCell(for indexPath: IndexPath) -> UITableViewCell? {
    
    if indexPath.section == 0 {
      
      let cell = tableView.dequeueReusableCell(withIdentifier: pigeonUsersCellID, for: indexPath) as! PigeonUsersTableViewCell
    
        if let name = filteredUsers[indexPath.row].name {
        
          cell.title.text = name
        }
      
        if let status = filteredUsers[indexPath.row].onlineStatus {
          if status == statusOnline {
            cell.subtitle.textColor = PigeonPalette.pigeonPaletteBlue
            cell.subtitle.text = status
            
          } else {
            let date = NSDate(timeIntervalSince1970:  status.doubleValue )
            cell.subtitle.textColor = UIColor.lightGray
            cell.subtitle.text = "last seen " + timeAgoSinceDate(date: date, timeinterval: status.doubleValue, numericDates: false)
          }
        } else {
          
          cell.subtitle.text = ""
        }
      
        if let url = filteredUsers[indexPath.row].thumbnailPhotoURL {          
          cell.icon.sd_setImage(with: URL(string: url), placeholderImage:  UIImage(named: "UserpicIcon"), options: [.progressiveDownload, .continueInBackground], completed: { (image, error, cacheType, url) in
            if image != nil {
              if (cacheType != SDImageCacheType.memory && cacheType != SDImageCacheType.disk) {
                cell.icon.alpha = 0
                UIView.animate(withDuration: 0.25, animations: {
                  cell.icon.alpha = 1
                })
              } else {
                cell.icon.alpha = 1
              }
            }

          })
        }
      
      return cell
      
    } else if indexPath.section == 1 {
      
      let cell = tableView.dequeueReusableCell(withIdentifier: contactsCellID, for: indexPath) as! ContactsTableViewCell
      
      cell.icon.image = UIImage(named: "UserpicIcon")
      cell.title.text = filteredContacts[indexPath.row].givenName + " " + filteredContacts[indexPath.row].familyName
      
      return cell
    }
    
    return nil
  }
  
  
    var chatLogController:ChatLogController? = nil
    var autoSizingCollectionViewFlowLayout:AutoSizingCollectionViewFlowLayout? = nil
  
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
      
      if indexPath.section == 0 {
        
        autoSizingCollectionViewFlowLayout = AutoSizingCollectionViewFlowLayout()
        autoSizingCollectionViewFlowLayout?.minimumLineSpacing = 5
        chatLogController = ChatLogController(collectionViewLayout: autoSizingCollectionViewFlowLayout!)
        chatLogController?.delegate = self
        chatLogController?.hidesBottomBarWhenPushed = true
        chatLogController?.user = filteredUsers[indexPath.row]
      }
    
      if indexPath.section == 1 {
        let destination = ContactsDetailController()
        destination.contactName = filteredContacts[indexPath.row].givenName + " " + filteredContacts[indexPath.row].familyName
        destination.contactPhoneNumbers.removeAll()
        destination .hidesBottomBarWhenPushed = true
        for phoneNumber in filteredContacts[indexPath.row].phoneNumbers {
          destination.contactPhoneNumbers.append(phoneNumber.value.stringValue)
        }
        self.navigationController?.pushViewController(destination, animated: true)
      }
    }
}


extension ContactsController: UITableViewDataSourcePrefetching {
  
  func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
    let urls = users.map { URL(string: $0.photoURL!)  }
    SDWebImagePrefetcher.shared().prefetchURLs(urls as? [URL])
  }
}


extension ContactsController: UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {}
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
     
        searchBar.text = nil
        filteredUsers = users
        
        tableView.reloadData()
    }
    
  
 func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    
    filteredUsers = searchText.isEmpty ? users : users.filter({ (User) -> Bool in
      return User.name!.lowercased().contains(searchText.lowercased())
    })
    
    filteredContacts = searchText.isEmpty ? contacts : contacts.filter({ (CNContact) -> Bool in
      return CNContact.givenName.lowercased().contains(searchText.lowercased())
    })

    tableView.reloadData()
  }
}

extension ContactsController { /* hiding keyboard */
  
  override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    
    if #available(iOS 11.0, *) {
        searchContactsController?.resignFirstResponder()
        searchContactsController?.searchBar.resignFirstResponder()
    } else {
         searchBar?.resignFirstResponder()
    }
  }
    
  
  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    
    if #available(iOS 11.0, *) {
        searchContactsController?.searchBar.endEditing(true)
    } else {
        self.searchBar?.endEditing(true)
    }
  }
}

extension ContactsController: MessagesLoaderDelegate {
  
  func messagesLoader( didFinishLoadingWith messages: [Message]) {
    
    self.chatLogController?.messages = messages
    
    var indexPaths = [IndexPath]()
    
    if messages.count - 1 >= 0 {
      for index in 0...messages.count - 1 {
        
        indexPaths.append(IndexPath(item: index, section: 0))
      }
      
      UIView.performWithoutAnimation {
        DispatchQueue.main.async {
          self.chatLogController?.collectionView?.reloadItems(at:indexPaths)
        }
      }
    }
    
    self.chatLogController?.startCollectionViewAtBottom()
    if let destination = self.chatLogController {
      navigationController?.pushViewController( destination, animated: true)
      self.chatLogController = nil
      self.autoSizingCollectionViewFlowLayout = nil
    }
    
  }
}


