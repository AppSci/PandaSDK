//
//  ViewController.swift
//  Example
//
//  Created by Kuts on 02.07.2020.
//  Copyright © 2020 PandaSDK. All rights reserved.
//

import UIKit
import PandaSDK

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }


    @IBAction func onShowTap(_ sender: Any) {
        Panda.shared.getScreen(screenId: "0fe27e07-a104-48bc-b558-e5afce061c3a") { [weak self] (result) in
            switch result {
            case .success(let vc):
                self?.present(vc, animated: true, completion: nil)
            case .failure(let error):
                print("Screen: \(error)")
            }
        }
    }
}
